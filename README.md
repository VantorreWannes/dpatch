# dpatch

Delta Patching Library.

## Testing

You can run the tests for this project using the following command:
```bash
zig build test
```

## Benchmarking

A benchmark suite is included to test the performance of `DPatchEncoder`. You can run it with:

```bash
zig build bench
```

## Docs

You can build the docs for this project using the following command:
```bash
zig build docs
```

and you can view them using 
```bash
python -m http.server 8000 -d zig-out/docs/
```