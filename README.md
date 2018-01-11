# Pony CBOR

### Behaviour

- Duplicate map keys will not cause an error, the value is just overwritten.

### Current limitations

- No support for indefinite length data items.
- No interpretation of tagged data; so no bignums, no fractions etc.
- No stream decoding

If you need any of these let me know or create a PR.

