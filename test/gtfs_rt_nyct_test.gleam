import gleam/int
import gleam/io
import gleam/list
import gleamy/bench
import gleeunit
import gtfs_rt_nyct
import protobin
import simplifile as file

pub fn main() -> Nil {
  gleeunit.main()
}

pub opaque type TestOptions(a) {
  Timeout(time: Int, function: fn() -> a)
}

pub fn gtfs_rt_1234567s_test() -> Nil {
  let path = "./test/gtfs-rt-nyct.pb"
  let assert Ok(bits) = file.read_bits(from: path)
  let assert Ok(protobin.Parsed(value: gtfs, ..)) =
    protobin.parse_with_config(
      from: bits,
      using: gtfs_rt_nyct.feed_message_decoder(),
      config: protobin.Config(ignore_groups: True),
    )

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 445
}

pub fn gtfs_rt_nqrw_test() -> Nil {
  let path = "./test/nyct_gtfs-nqrw.pb"
  let assert Ok(bits) = file.read_bits(from: path)
  let assert Ok(protobin.Parsed(value: gtfs, ..)) =
    protobin.parse_with_config(
      from: bits,
      using: gtfs_rt_nyct.feed_message_decoder(),
      config: protobin.Config(ignore_groups: True),
    )

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 250
}

pub fn benchmark_test_() {
  use <- Timeout(10_000)

  let path = "./test/gtfs-rt-nyct.pb"
  let assert Ok(gtfs_1234567s) = file.read_bits(from: path)

  let path = "./test/nyct_gtfs-nqrw.pb"
  let assert Ok(gtfs_nqrw) = file.read_bits(from: path)

  let res =
    bench.run(
      [
        bench.Input("1234567S gtfs", gtfs_1234567s),
        bench.Input("NQRW gtfs", gtfs_nqrw),
      ],
      [
        bench.Function("protobin.parse()", protobin.parse_with_config(
          from: _,
          using: gtfs_rt_nyct.feed_message_decoder(),
          config: protobin.Config(ignore_groups: False),
        )),
      ],
      [bench.Duration(9000)],
    )

  let mean_ms =
    list_mean(res.sets, fn(set) { list_mean(set.reps, fn(time) { time }) })
  assert mean_ms <. 350.0

  io.println(
    "\n"
    <> bench.table(res, [
      bench.IPS,
      bench.Min,
      bench.Max,
      bench.Mean,
      bench.SD,
      bench.SDPercent,
    ]),
  )
}

fn list_mean(list: List(a), to_float: fn(a) -> Float) -> Float {
  let total =
    list.fold(over: list, from: 0.0, with: fn(acc, elem) {
      acc +. to_float(elem)
    })
  total /. int.to_float(list.length(list))
}
