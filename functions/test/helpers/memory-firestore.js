'use strict';
// Test double for domain/service unit tests. Does NOT validate Firestore rules,
// indexes, network transport or real contention; emulator tests remain required.
function clone(value) {
  if (value === null || typeof value !== 'object') return value;
  if (value.constructor?.name === 'ServerTimestampTransform') return new Date('2026-11-20T12:00:00Z');
  if (value instanceof Date) return new Date(value);
  if (typeof value.toDate === 'function') return value;
  if (Array.isArray(value)) return value.map(clone);
  return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, clone(v)]));
}
class Reference {
  constructor(db, path) { this.db = db; this.path = path; this.id = path.split('/').at(-1); }
  async get() { return this.db.snapshot(this.path); }
  async set(data, options) { this.db.write(this.path, data, options?.merge ? 'merge' : 'set'); }
  async create(data) { this.db.write(this.path, data, 'create'); }
  async update(data) { this.db.write(this.path, data, 'update'); }
}
class Query {
  constructor(db, col, filters = [], cap = Infinity, after = '') { Object.assign(this, {db, col, filters, cap, after}); }
  doc(id) { return new Reference(this.db, `${this.col}/${id}`); }
  where(field, op, value) { return new Query(this.db, this.col, [...this.filters, [field, op, value]], this.cap, this.after); }
  orderBy() { return this; }
  limit(cap) { return new Query(this.db, this.col, this.filters, cap, this.after); }
  startAfter(snap) { return new Query(this.db, this.col, this.filters, this.cap, snap.id); }
  async get() {
    const docs = [...this.db.docs.keys()].filter(path => path.split('/').length === 2 && path.startsWith(`${this.col}/`))
      .sort().map(path => this.db.snapshot(path)).filter(s => s.id > this.after)
      .filter(s => this.filters.every(([field, op, value]) => {
        const actual = s.data()[field];
        if (op === '==') return actual === value;
        if (op === 'array-contains') return Array.isArray(actual) && actual.includes(value);
        throw new Error(`Unsupported query operator ${op}`);
      })).slice(0, this.cap);
    return {docs, size: docs.length, empty: docs.length === 0};
  }
}
class MemoryFirestore {
  constructor(seed = {}) { this.docs = new Map(Object.entries(seed).map(([k, v]) => [k, clone(v)])); this.tail = Promise.resolve(); }
  collection(name) { return new Query(this, name); }
  doc(path) { return new Reference(this, path); }
  snapshot(path) {
    const value = this.docs.get(path);
    return {id: path.split('/').at(-1), exists: value !== undefined,
      ref: this.doc(path), data: () => clone(value)};
  }
  write(path, data, kind) {
    if (kind === 'create' && this.docs.has(path)) throw new Error('already-exists');
    if (kind === 'update' && !this.docs.has(path)) throw new Error('not-found');
    this.docs.set(path, kind === 'merge' || kind === 'update' ? {...this.docs.get(path), ...clone(data)} : clone(data));
  }
  async runTransaction(callback) {
    const run = this.tail.then(async () => {
      const writes = []; let writing = false;
      const tx = {
        get: async ref => {
          if (writing) throw new Error('Firestore requires all reads before writes');
          return ref.get();
        },
        create: (ref, data) => { writing = true; writes.push([ref.path, data, 'create']); },
        set: (ref, data, opts) => { writing = true; writes.push([ref.path, data, opts?.merge ? 'merge' : 'set']); },
        update: (ref, data) => { writing = true; writes.push([ref.path, data, 'update']); },
      };
      const result = await callback(tx);
      const before = new Map(this.docs);
      try { for (const [path, data, kind] of writes) this.write(path, data, kind); }
      catch (e) { this.docs = before; throw e; }
      return result;
    });
    this.tail = run.catch(() => {});
    return run;
  }
  data(path) { return this.snapshot(path).data(); }
  paths(col) { return [...this.docs.keys()].filter(p => p.startsWith(`${col}/`)); }
}
module.exports = {MemoryFirestore};
