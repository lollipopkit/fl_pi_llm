// pi-durable's `SqliteDatabase`, over a chat's SQLite file.
//
// A chat is a pi-durable `SqliteStorage` of its own, in one file the engine
// keeps (rust/src/db.rs). The engine answers synchronously:
//
//   __host.dbOpen(id)                     -> handle, the file created if new
//   __host.dbClose(handle)
//   __host.dbExec(handle, sql)            several statements, no bindings
//   __host.dbQuery(handle, sql, params, mode)
//                                         mode 0: run; 1: first row or
//                                         undefined; 2: every row
//   __host.dbList()                       -> [{id, createdAt, modifiedAt}]
//   __host.dbRemove(id)
//   __host.cacheGet(key)                  -> string | undefined
//   __host.cacheSet(key, value | null)    what can be fetched again
//
// Rows come back as objects by column name, integers as numbers.

const host = globalThis.__host;

/** Every stored chat: `{id, createdAt, modifiedAt}`. */
export const listChats = () => host.dbList();

/** Deletes chat [id]'s file. It must not be open. */
export const removeChat = (id) => host.dbRemove(id);

class Executor {
  constructor(handle) {
    this.handle = handle;
  }

  exec(sql) {
    return this.op(() => host.dbExec(this.handle, sql));
  }

  run(sql, ...params) {
    return this.op(() => { host.dbQuery(this.handle, sql, params, 0); });
  }

  get(sql, ...params) {
    return this.op(() => host.dbQuery(this.handle, sql, params, 1));
  }

  all(sql, ...params) {
    return this.op(() => host.dbQuery(this.handle, sql, params, 2));
  }
}

/** Valid only while its transaction's callback runs. */
class Transaction extends Executor {
  constructor(handle, scope) {
    super(handle);
    this.scope = scope;
  }

  async op(fn) {
    if (!this.scope.active) throw new Error('SQLite transaction handle is no longer active');
    return fn();
  }
}

/**
 * Chat [id]'s database, as `SqliteStorage.open` takes one. Operations run in
 * call order; a transaction holds the queue until it settles.
 */
class ChatDatabase extends Executor {
  #tail = Promise.resolve();

  op(fn) {
    const run = this.#tail.then(fn);
    this.#tail = run.then(() => {}, () => {});
    return run;
  }

  transaction(callback) {
    return this.op(async () => {
      host.dbExec(this.handle, 'BEGIN IMMEDIATE');
      const scope = { active: true };
      try {
        const result = await callback(new Transaction(this.handle, scope));
        scope.active = false;
        host.dbExec(this.handle, 'COMMIT');
        return result;
      } catch (e) {
        scope.active = false;
        try {
          host.dbExec(this.handle, 'ROLLBACK');
        } catch (rollback) {
          throw new AggregateError([e, rollback], 'SQLite rollback failed');
        }
        throw e;
      }
    });
  }

  close() {
    return this.op(() => host.dbClose(this.handle));
  }
}

/** Opens chat [id]'s database, creating it when there is none. */
export const openChat = (id) => new ChatDatabase(host.dbOpen(id));
