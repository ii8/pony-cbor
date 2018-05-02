use "buffered"
use "collections"

type CborType is
  ( None
  | Bool
  | Number
  | Array[U8] val
  | String
  | CborArray
  | CborMap
  | CborTag
  | CborSimple )

type CborMapType is HashMap[CborType, CborType, CborHash]

primitive Cbor
  fun encode(w: Writer, c: CborType) =>
    match c
    | None =>
      w.u8(0xf6)

    | let b: Bool =>
      w.u8(if b then 0xf5 else 0xf4 end)

    | let u: Unsigned =>
      _write_n(w, 0, u.u64())

    | let i: Signed =>
      let i' = i.i128()
      if i' < 0 then _write_n(w, 0x20, (-1 - i').u64())
      else _write_n(w, 0, i.u64())
      end

    | let f: F32 =>
      w.>u8(0xfa).f32_be(f)

    | let f: F64 =>
      w.>u8(0xfb).f64_be(f)

    | let b: Array[U8] val =>
      _write_n(w, 0x40, b.size().u64())
      w.write(b)

    | let s: String =>
      _write_n(w, 0x60, s.size().u64())
      w.write(s)

    | let a: CborArray =>
      _write_n(w, 0x80, a.items.size().u64())
      for i in a.items.values() do encode(w, i) end

    | let m: CborMap =>
      _write_n(w, 0xa0, m.pairs.size().u64())
      for (k, v) in m.pairs.pairs() do encode(w, k); encode(w, v) end

    | let t: CborTag =>
      _write_n(w, 0xc0, t.value.u64())
      encode(w, t.item)

    | let s: CborSimple =>
      _write_n(w, 0xe0, s.value.u64())
    end

  fun _write_n(w: Writer, mt: U8, u: U64) =>
    if u < 24 then
      w.u8(mt or u.u8())
    elseif u < 256 then
      w.>u8(mt or 0x18).u8(u.u8())
    elseif u < 65536 then
      w.>u8(mt or 0x19).u16_be(u.u16())
    elseif u < 4294967296 then
      w.>u8(mt or 0x1a).u32_be(u.u32())
    else
      w.>u8(mt or 0x1b).u64_be(u.u64())
    end

  fun decode(r: Reader): CborType ? =>
    let ib: U8 = r.u8()?
    let mt: U8 = ib >> 5
    let ai: U8 = ib and 0x1f

    match mt
    | 0 => _read_positive(r, ai)?
    | 1 => _read_negative(r, ai)?
    | 2 => _read_bytes(r, ai)?
    | 3 => _read_text(r, ai)?
    | 4 => _read_array(r, ai)?
    | 5 => _read_map(r, ai)?
    | 6 => _read_tag(r, ai)?
    | 7 => _read_mt7(r, ai)?
    end

  fun _read_n(r: Reader, ai: U8): (U8 | U16 | U32 | U64) ? =>
    if ai < 24 then
      ai
    else
      match ai
      | 24 => r.u8()?
      | 25 => r.u16_be()?
      | 26 => r.u32_be()?
      | 27 => r.u64_be()?
      else
        error
      end
    end

  fun _read_positive(r: Reader, ai: U8): Unsigned ? =>
    _read_n(r, ai)?

  fun _read_negative(r: Reader, ai: U8): (I64 | I128) ? =>
    let i = _read_n(r, ai)?.i128().neg() - 1
    if i > I64.min_value().i128() then i.i64() else i end

  fun _read_bytes(r: Reader, ai: U8): Array[U8] val ? =>
    r.block(_read_n(r, ai)?.usize())?

  fun _read_text(r: Reader, ai: U8): String ? =>
    String.from_array(_read_bytes(r, ai)?)

  fun _read_array(r: Reader, ai: U8): CborArray ? =>
    let n = _read_n(r, ai)?.usize()
    var i = USize(0)
    let a: Array[CborType] iso = recover Array[CborType](n) end
    while i < n do
      a.push(decode(r)?)
      i = i + 1
    end
    CborArray(consume a)

  fun _read_map(r: Reader, ai: U8): CborMap ? =>
    let n = _read_n(r, ai)?.usize()
    var i = USize(0)
    let m: CborMapType iso = recover CborMapType(n) end
    while i < n do
      let k = decode(r)?
      let v = decode(r)?
      m.insert(k, v)?
      i = i + 1
    end
    CborMap(consume m)

  fun _read_tag(r: Reader, ai: U8): CborTag ? =>
    let n = _read_n(r, ai)?
    CborTag(n, decode(r)?)

  fun _read_mt7(r: Reader, ai: U8): (None | Bool | CborSimple | Float) ? =>
    if ai < 20 then
      CborSimple(ai)
    else
      match ai
      | 20 => false
      | 21 => true
      | 22 => None
      | 23 => CborSimple(23)
      | 24 =>
        let s = r.u8()?
        if (s > 23) then
          CborSimple(s)
        else
          error
        end
      | 25 => _decode_f16(r.u16_be()?)?
      | 26 => r.f32_be()?
      | 27 => r.f64_be()?
      else
        error
      end
    end

  fun _decode_f16(f: U16): F64 ? =>
    let exp = (f >> 10) and 0x1f
    let sig = (f and 0x3ff).f64()
    let d: F64 =
      if exp == 0 then F64.ldexp(sig, -24)
      elseif exp != 31 then F64.ldexp(sig + 1024, exp.i32() - 25)
      else error end
    if (f and 0x8000) > 0 then -d else d end

class val CborArray
  let items: Array[CborType] val

  new val create(a: Array[CborType] val) =>
    items = a

  fun hash(): USize =>
    /* If anyone ever needs performace for arrays as map keys(unlikely) then
     * implement something more advanced here */
    items.size()

  fun eq(c: CborType): Bool =>
    try
      let a = c as CborArray
      for (i, v) in items.pairs() do
        if not CborHash.eq(a.items(i)?, v) then
          return false
        end
      end
    else
      false
    end
    true

class val CborMap
  let pairs: CborMapType val

  new val create(m: CborMapType val) =>
    pairs = m

  new val from_array(a: Array[CborType] val) =>
    pairs = recover val
      let s = a.size()
      let m = CborMapType((s + if (s % 2) == 0 then 0 else 1 end) / 2)
      let i = a.values()
      while i.has_next() do
        try
          let k = i.next()?
          let v = if i.has_next() then i.next()? else None end
          m.insert(k, v)?
        end
      end
      m
    end

  fun hash(): USize =>
    digestof pairs

  fun eq(c: CborType): Bool =>
    false

class val CborTag
  let value: (U8 | U16 | U32 | U64)
  let item: CborType

  new val create(value': (U8 | U16 | U32 | U64), item': CborType) =>
    value = value'
    item = item'

  fun hash(): USize =>
    CborHash.hash(item)

class val CborSimple
  let value: U8

  new val create(value': U8) =>
    value = value'

  fun hash(): USize =>
    value.usize()

  fun eq(c: CborType): Bool =>
    try
      let s = c as CborSimple
      value == s.value
    else
      false
    end

primitive CborHash is HashFunction[CborType]
  fun hash(c: CborType): USize =>
    match c
    | None => 9000
    | let b: Bool => if b then 9001 else 9002 end
    | let x: (Number | String | CborArray | CborMap | CborTag | CborSimple) =>
      x.hash()
    | let b: Array[U8] val => String.from_array(b).hash()
    end

  fun eq(c: CborType, c': CborType): Bool =>
    try
      match c'
      | let x: CborTag => return eq(x.item, c)
      end
      match c
      | let x: (None | Bool) => x is c'
      | let n: Number => n.i128() == (c' as Number).i128()
      | let b: Array[U8] val =>
        String.from_array(b) == String.from_array(c' as Array[U8] val)
      | let s: String => s == (c' as String)
      | let x: (CborArray | CborMap | CborSimple) => x == c'
      | let t: CborTag => eq(t.item, c')
      end
    else
      false
    end
