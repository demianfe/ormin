
{.deadCodeElim: on.}

import strutils, sqlite3, json

import db_common
export db_common

type
  DbConn* = PSqlite3  ## encapsulates a database connection
  varchar* = string
  integer* = int
  timestamp* = string

proc dbError*(db: DbConn) {.noreturn.} =
  ## raises a DbError exception.
  var e: ref DbError
  new(e)
  e.msg = $sqlite3.errmsg(db)
  raise e

proc prepareStmt*(db: DbConn; q: string): PStmt =
  if prepare_v2(db, q, q.len.cint, result, nil) != SQLITE_OK:
    dbError(db)

template startBindings*(s: PStmt; n: int) =
  if clear_bindings(s) != SQLITE_OK: dbError(db)

template bindParam*(db: DbConn; s: PStmt; idx: int; x, t: untyped) =
  #when not (x is t):
  #  {.error: "type mismatch for query argument at position " & $idx.}
  when t is int or t is int64 or t is bool:
    if bind_int64(s, idx.cint, x.int64) != SQLITE_OK: dbError(db)
  elif t is string:
    if bind_blob(s, idx.cint, cstring(x), x.len.cint, SQLITE_STATIC) != SQLITE_OK:
      dbError(db)
  elif t is float64:
    if bind_double(s, idx.cint, x) != SQLITE_OK:
      dbError(db)
  else:
    {.error: "type mismatch for query argument at position " & $idx.}

template bindParamJson*(db: DbConn; s: PStmt; idx: int; xx: JsonNode;
                        t: typedesc) =
  let x = xx
  if x.kind == JNull:
    if bind_null(s, idx.cint) != SQLITE_OK: dbError(db)
  else:
    when t is string:
      doAssert x.kind == JString
      let xs = x.str
      if bind_blob(s, idx.cint, cstring(xs), xs.len.cint, SQLITE_STATIC) != SQLITE_OK:
        dbError(db)
    elif (t is int) or (t is int64):
      doAssert x.kind == JInt
      let xi = x.num
      if bind_int64(s, idx.cint, xi.int64) != SQLITE_OK: dbError(db)
    elif t is float64:
      doAssert x.kind == JFloat
      let xf = x.fnum
      if bind_double(s, idx.cint, xf) != SQLITE_OK:
        dbError(db)
    elif t is bool:
      doAssert x.kind == JBool
      let xb = x.bval
      if bind_int64(s, idx.cint, xb.int64) != SQLITE_OK: dbError(db)
    else:
      {.error: "invalid type for JSON object".}

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: int;
                     t: typedesc; name: string) =
  dest = int column_int64(s, idx.cint)

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: int64;
                     t: typedesc; name: string) =
  dest = column_int64(s, idx.cint)

proc fillString(dest: var string; src: cstring; srcLen: int) =
  when defined(nimNoNilSeqs):
    setLen(dest, srcLen)
  else:
    if dest.isNil: dest = newString(srcLen)
    else: setLen(dest, srcLen)
  copyMem(unsafeAddr(dest[0]), src, srcLen)
  dest[srcLen] = '\0'

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: var string;
                     t: typedesc; name: string) =
  let srcLen = column_bytes(s, idx.cint)
  let src = column_text(s, idx.cint)
  fillString(dest, src, srcLen)

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: float64;
                     t: typedesc; name: string) =
  dest = column_double(s, idx.cint)

template bindResult*(db: DbConn; s: PStmt; idx: int; dest: bool;
                     t: typedesc; name: string) =
  dest = column_int64(s, idx.cint) != 0

template createJObject*(): untyped = newJObject()
template createJArray*(): untyped = newJArray()

template bindResultJson*(db: DbConn; s: PStmt; idx: int; obj: JsonNode;
                         t: typedesc; name: string) =
  let x = obj
  doAssert x.kind == JObject
  if column_type(s, idx.cint) == SQLITE_NULL:
    x[name] = newJNull()
  else:
    when t is string:
      let dest = newJString("")
      let srcLen = column_bytes(s, idx.cint)
      let src = column_text(s, idx.cint)
      fillString(dest.str, src, srcLen)
      x[name] = dest
    elif (t is int) or (t is int64):
      x[name] = newJInt(column_int64(s, idx.cint))
    elif t is float64:
      x[name] = newJFloat(column_double(s, idx.cint))
    elif t is bool:
      x[name] = newJBool(column_int64(s, idx.cint) != 0)
    else:
      {.error: "invalid type for JSON object".}

template startQuery*(db: DbConn; s: PStmt) = discard "nothing to do"

template stopQuery*(db: DbConn; s: PStmt) =
  if sqlite3.reset(s) != SQLITE_OK: dbError(db)

template stepQuery*(db: DbConn; s: PStmt; returnsData: int): bool =
  when returnsData == 1:
    step(s) == SQLITE_ROW
  else:
    step(s) == SQLITE_DONE

template getLastId*(db: DbConn; s: PStmt): int =
  int(last_insert_rowid(db))

template getAffectedRows*(db: DbConn; s: PStmt): int =
  int(changes(db))

proc close*(db: DbConn) =
  ## closes the database connection.
  if sqlite3.close(db) != SQLITE_OK: dbError(db)

proc open*(connection, user, password, database: string): DbConn =
  ## opens a database connection. Raises `EDb` if the connection could not
  ## be established. Only the ``connection`` parameter is used for ``sqlite``.
  if sqlite3.open(connection, result) != SQLITE_OK:
    dbError(result)
