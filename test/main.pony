use "ponytest"
use "buffered"
use "collections"
use "../cbor"

actor Main is TestList
  new create(env: Env) => PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_EncodeUnsigned)
    test(_EncodeSigned)
    test(_EncodeFloat)
    test(_EncodeBytes)
    test(_EncodeText)
    test(_EncodeArray)
    test(_EncodeMap)
    test(_EncodeTag)
    test(_EncodeSimple)

    test(_DecodeUnsigned)
    test(_DecodeSigned)
    test(_DecodeFloat)
    test(_DecodeBytes)
    test(_DecodeText)
    test(_DecodeArray)
    test(_DecodeMap)
    test(_DecodeTag)
    test(_DecodeSimple)

primitive _H
  fun equal_array(a: CborArray, c: CborType): Bool ? =>
    let b = c as CborArray
    for (i, v) in a.items.pairs() do
      if not equal(b.items(i)?, v) then
        return false
      end
    end
    true

  fun equal_map(a: CborMap, c: CborType): Bool ? =>
    let b = c as CborMap
    for (k, v) in a.pairs.pairs() do
      if not equal(b.pairs(k)?, v) then
        return false
      end
    end
    true

  fun equal_tag(a: CborTag, c: CborType): Bool ? =>
    let b = c as CborTag
    (a.value is b.value) and equal(a.item, b.item)

  fun equal_simple(a: CborSimple, c: CborType): Bool ? =>
    let b = c as CborSimple
    a.value == b.value

  fun equal(a': CborType, b: CborType): Bool =>
    try
      match a'
      | let a: (None | Bool | Number) => a is b
      | let a: Array[U8] val => String.from_array(a) == String.from_array(b as Array[U8] val)
      | let a: String => a == (b as String)
      | let a: CborArray => equal_array(a, b)?
      | let a: CborMap => equal_map(a, b)?
      | let a: CborTag => equal_tag(a, b)?
      | let a: CborSimple => equal_simple(a, b)?
      end
    else
      false
    end

  fun enc(h: TestHelper, c: CborType, r: Array[U8] box) =>
    let w = recover ref Writer end
    Cbor.encode(w, c)
    let r' = Array[U8]
    for chunk in w.done().values() do
      r'.append(chunk)
    end
    h.assert_array_eq[U8](r, r')

  fun dec(h: TestHelper, d: Array[U8] val, c: CborType) =>
    let r = Reader
    r.append(d)
    try
      let result = Cbor.decode(consume r)?
      h.assert_true(equal(result, c))
    end

class iso _EncodeUnsigned is UnitTest
  fun name(): String => "encode.unsigned"

  fun apply(h: TestHelper) =>
    _H.enc(h, U32(0), [0x00])
    _H.enc(h, U16(1), [0x01])
    _H.enc(h, U8(13), [0x0d])
    _H.enc(h, U8(23), [0x17])
    _H.enc(h, U32(24), [0x18; 0x18])
    _H.enc(h, U32(101), [0x18; 0x65])
    _H.enc(h, U128(1000000), [0x1a; 0x00; 0x0f; 0x42; 0x40])
    _H.enc(h, U64(1000000000000),
      [0x1b; 0x00; 0x00; 0x00; 0xe8; 0xd4; 0xa5; 0x10; 0x00])
    _H.enc(h, U64(18446744073709551615),
      [0x1b; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff])

class iso _EncodeSigned is UnitTest
  fun name(): String => "encode.signed"

  fun apply(h: TestHelper) =>
    _H.enc(h, I32(0), [0x00])
    _H.enc(h, I32(1000000), [0x1a; 0x00; 0x0f; 0x42; 0x40])
    _H.enc(h, I32(-1), [0x20])
    _H.enc(h, I32(-2), [0x21])
    _H.enc(h, I64(-24), [0x37])
    _H.enc(h, I8(-25), [0x38; 0x18])
    _H.enc(h, I32(-1000000), [0x3A; 0x00; 0x0F; 0x42; 0x3F])
    _H.enc(h, I128(-18446744073709551616),
      [0x3b; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff])

class iso _EncodeFloat is UnitTest
  fun name(): String => "encode.float"

  fun apply(h: TestHelper) =>
    _H.enc(h, F32(0), [0xfa; 0x00; 0x00; 0x00; 0x00])
    _H.enc(h, F64(1.1), [0xfb; 0x3f; 0xf1; 0x99; 0x99; 0x99; 0x99; 0x99; 0x9a])
    _H.enc(h, F32(3.4028234663852886e+38), [0xfa; 0x7f; 0x7f; 0xff; 0xff])
    _H.enc(h, F32.from_bits(0x7f800000), [0xfa; 0x7f; 0x80; 0x00; 0x00])
    _H.enc(h, F32.from_bits(0x7fffffff), [0xfa; 0x7f; 0xff; 0xff; 0xff])

class iso _EncodeBytes is UnitTest
  fun name(): String => "encode.bytes"

  fun apply(h: TestHelper) =>
    _H.enc(h, [0x02], [0x41; 0x02])
    _H.enc(h,
      recover val Array[U8].init(12, 30) end,
      Array[U8].init(12, 30).>unshift(0x1e).>unshift(0x58))

class iso _EncodeText is UnitTest
  fun name(): String => "encode.text"

  fun apply(h: TestHelper) =>
    _H.enc(h, "", [0x60])
    _H.enc(h, "AB", [0x62; 0x41; 0x42])
    _H.enc(h,
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
      Array[U8].init(0x41, 30).>unshift(0x1e).>unshift(0x78))
    _H.enc(h, "水", [0x63; 0xe6; 0xb0; 0xb4])

class iso _EncodeArray is UnitTest
  fun name(): String => "encode.array"

  fun apply(h: TestHelper) =>
    _H.enc(h, CborArray([]), [0x80])
    _H.enc(h, CborArray([I32(1); I32(2); U64(3)]), [0x83; 0x01; 0x02; 0x03])
    _H.enc(h,
      CborArray([U8(1); CborArray([U8(2); I8(3)]); CborArray([U8(4); U8(5)])]),
      [0x83; 0x01; 0x82; 0x02; 0x03; 0x82; 0x04; 0x05])

class iso _EncodeMap is UnitTest
  fun name(): String => "encode.map"

  fun apply(h: TestHelper) =>
    _H.enc(h, CborMap(recover val CborMapType end), [0xa0])
    try
      let m = recover iso
        CborMapType.>insert(U32(1), I8(2))?.>insert(U64(3), I32(4))?
      end
      _H.enc(h, CborMap(consume m), [0xa2; 0x03; 0x04; 0x01; 0x02])
    end
    _H.enc(h, CborMap.from_array([U32(1); I8(2)]), [0xa1; 0x01; 0x02])

class iso _EncodeTag is UnitTest
  fun name(): String => "encode.tag"

  fun apply(h: TestHelper) =>
    _H.enc(h, CborTag(U8(4), CborArray([I8(-2); U32(27315)])),
      [0xc4; 0x82; 0x21; 0x19; 0x6a; 0xb3])

class iso _EncodeSimple is UnitTest
  fun name(): String => "encode.simple"

  fun apply(h: TestHelper) =>
    _H.enc(h, false, [0xf4])
    _H.enc(h, true, [0xf5])
    _H.enc(h, None, [0xf6])
    _H.enc(h, CborSimple(12), [0xec])
    _H.enc(h, CborSimple(40), [0xf8; 0x28])
    _H.enc(h, CborSimple(0xff), [0xf8; 0xff])

class iso _DecodeUnsigned is UnitTest
  fun name(): String => "decode.unsigned"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0x00], U8(0))
    _H.dec(h, [0x01], U8(1))
    _H.dec(h, [0x0d], U8(13))
    _H.dec(h, [0x17], U8(23))
    _H.dec(h, [0x18; 0x18], U8(24))
    _H.dec(h, [0x18; 0x65], U8(101))
    _H.dec(h, [0x1a; 0x00; 0x0f; 0x42; 0x40], U32(1000000))
    _H.dec(h, [0x1b; 0x00; 0x00; 0x00; 0xe8; 0xd4; 0xa5; 0x10; 0x00],
      U64(1000000000000))
    _H.dec(h, [0x1b; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff],
      U64(18446744073709551615))

class iso _DecodeSigned is UnitTest
  fun name(): String => "decode.signed"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0x20], I64(-1))
    _H.dec(h, [0x21], I64(-2))
    _H.dec(h, [0x37], I64(-24))
    _H.dec(h, [0x38; 0x18], I64(-25))
    _H.dec(h, [0x3A; 0x00; 0x0F; 0x42; 0x3F], I64(-1000000))
    _H.dec(h, [0x3b; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff; 0xff],
      I128(-18446744073709551616))

class iso _DecodeFloat is UnitTest
  fun name(): String => "decode.float"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0xf9; 0x00; 0x00], F64(0.0))
    _H.dec(h, [0xf9; 0x80; 0x00], F64(-0.0))
    _H.dec(h, [0xfa; 0x00; 0x00; 0x00; 0x00], F32(0))
    _H.dec(h, [0xfb; 0x3f; 0xf1; 0x99; 0x99; 0x99; 0x99; 0x99; 0x9a], F64(1.1))
    _H.dec(h, [0xfa; 0x7f; 0x7f; 0xff; 0xff], F32(3.4028234663852886e+38))
    _H.dec(h, [0xfa; 0x7f; 0x80; 0x00; 0x00], F32.from_bits(0x7f800000))
    _H.dec(h, [0xfa; 0x7f; 0xff; 0xff; 0xff], F32.from_bits(0x7fffffff))

class iso _DecodeBytes is UnitTest
  fun name(): String => "decode.bytes"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0x41; 0x02], [0x02])
    _H.dec(h,
      recover val Array[U8].init(12, 30).>unshift(0x1e).>unshift(0x58) end,
      recover val Array[U8].init(12, 30) end)

class iso _DecodeText is UnitTest
  fun name(): String => "decode.text"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0x60], "")
    _H.dec(h, [0x62; 0x41; 0x42], "AB")
    _H.dec(h,
      recover val Array[U8].init(0x41, 30).>unshift(0x1e).>unshift(0x78) end,
      "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")
    _H.dec(h, [0x63; 0xe6; 0xb0; 0xb4], "水")

class iso _DecodeArray is UnitTest
  fun name(): String => "decode.array"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0x80], CborArray([]))
    _H.dec(h, [0x83; 0x01; 0x02; 0x03], CborArray([U8(1); U8(2); U8(3)]))
    _H.dec(h,
      [0x83; 0x01; 0x82; 0x02; 0x03; 0x82; 0x04; 0x05],
      CborArray([U8(1); CborArray([U8(2); U8(3)]); CborArray([U8(4); U8(5)])]))

class iso _DecodeMap is UnitTest
  fun name(): String => "decode.map"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0xa2; 0xc6; 0xf4; 0x01; 0xf4; 0x02],
      CborMap.from_array([false; U8(2)]))
    _H.dec(h, [0xa2; 0xf4; 0x01; 0xc6; 0xf4; 0x02],
      CborMap.from_array([CborTag(U8(0), false); U8(2)]))
    _H.dec(h, [ 0xa2; 0x62; 0x68; 0x69; 0x01; 0x63; 0x6c; 0x6f; 0x6c; 0x02],
      CborMap.from_array(["lol"; U8(2); "hi"; U8(1)]))
    _H.dec(h, [0xa2; 0x01; 0x00; 0x19; 0x00; 0x01; 0x00],
      CborMap.from_array([U8(1); U8(0)]))

class iso _DecodeTag is UnitTest
  fun name(): String => "decode.tag"

  fun apply(h: TestHelper) =>
    _H.dec(h, [0xc4; 0x82; 0x21; 0x19; 0x6a; 0xb3],
      CborTag(U8(4), CborArray([I64(-2); U16(27315)])))

class iso _DecodeSimple is UnitTest
  fun name(): String => "decode.simple"

  fun fail(h: TestHelper, b: U8) =>
    h.assert_error({() ? =>
      let r = Reader; r.append([0xf8; b]); Cbor.decode(consume r)? })

  fun apply(h: TestHelper) =>
    _H.dec(h, [0xf4], false)
    _H.dec(h, [0xf5], true)
    _H.dec(h, [0xf6], None)
    _H.dec(h, [0xec], CborSimple(12))
    _H.dec(h, [0xf8; 0x28], CborSimple(40))
    _H.dec(h, [0xf8; 0xff], CborSimple(0xff))
    fail(h, 0x14)
    fail(h, 0x15)
    fail(h, 0x16)
    fail(h, 0x17)
