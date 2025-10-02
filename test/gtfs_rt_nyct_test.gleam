import gleam/float
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

fn parse_gtfs_rt(
  lines lines: String,
) -> protobin.DecodeResult(protobin.Parsed(gtfs_rt_nyct.FeedMessage)) {
  let path = "./test/nyct_gtfs-" <> lines <> ".pb"
  let assert Ok(bits) = file.read_bits(from: path)
  protobin.parse_with_config(
    from: bits,
    using: gtfs_rt_nyct.feed_message_decoder(),
    config: protobin.Config(ignore_groups: True),
  )
}

pub fn gtfs_rt_ace_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "ace")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 260
}

pub fn gtfs_rt_bdfm_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "bdfm")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 338
}

pub fn gtfs_rt_g_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "g")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 50
}

pub fn gtfs_rt_jz_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "jz")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 64
}

pub fn gtfs_rt_nqrw_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "nqrw")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 250
}

pub fn gtfs_rt_l_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "l")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 53
}

pub fn gtfs_rt_1234567s_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) =
    parse_gtfs_rt(lines: "1234567s")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 445
}

pub fn gtfs_rt_1234567s_2_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) =
    parse_gtfs_rt(lines: "1234567s.2")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 457
}

pub fn gtfs_rt_si_test() -> Nil {
  let assert Ok(protobin.Parsed(value: gtfs, ..)) = parse_gtfs_rt(lines: "si")

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 14
}

pub fn benchmark_test_() {
  use <- Timeout(60_000)
  benchmark_inner(200.0)
}

// TODO: find way to run this just on JS
//       (see <https://github.com/lpil/gleeunit/issues/52>)
// pub fn benchmark_test() {
//   benchmark_inner(todo)
// }

pub fn benchmark_inner(time_to_beat: Float) {
  let assert Ok(gtfs_ace) = file.read_bits(from: "./test/nyct_gtfs-ace.pb")
  let assert Ok(gtfs_bdfm) = file.read_bits(from: "./test/nyct_gtfs-bdfm.pb")
  let assert Ok(gtfs_g) = file.read_bits(from: "./test/nyct_gtfs-g.pb")
  let assert Ok(gtfs_jz) = file.read_bits(from: "./test/nyct_gtfs-jz.pb")
  let assert Ok(gtfs_nqrw) = file.read_bits(from: "./test/nyct_gtfs-nqrw.pb")
  let assert Ok(gtfs_l) = file.read_bits(from: "./test/nyct_gtfs-l.pb")
  let assert Ok(gtfs_1234567s) =
    file.read_bits(from: "./test/nyct_gtfs-1234567s.pb")
  let assert Ok(gtfs_1234567s_2) =
    file.read_bits(from: "./test/nyct_gtfs-1234567s.2.pb")
  let assert Ok(gtfs_si) = file.read_bits(from: "./test/nyct_gtfs-si.pb")

  let res =
    bench.run(
      [
        bench.Input("ACE gtfs", gtfs_ace),
        bench.Input("BDFM gtfs", gtfs_bdfm),
        bench.Input("G gtfs", gtfs_g),
        bench.Input("JZ gtfs", gtfs_jz),
        bench.Input("NQRW gtfs", gtfs_nqrw),
        bench.Input("L gtfs", gtfs_l),
        bench.Input("1234567S gtfs", gtfs_1234567s),
        bench.Input("1234567S gtfs (2)", gtfs_1234567s_2),
        bench.Input("SI gtfs", gtfs_si),
      ],
      [
        bench.Function("protobin.parse()", protobin.parse_with_config(
          from: _,
          using: gtfs_rt_nyct.feed_message_decoder(),
          config: protobin.Config(ignore_groups: False),
        )),
      ],
      [bench.Duration(5000)],
    )

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

  let mean_ms =
    list_mean(res.sets, fn(set) { list_mean(set.reps, fn(time) { time }) })
  io.println("\nOverall mean: " <> float.to_string(mean_ms))
  io.println("\nTime to beat: " <> float.to_string(time_to_beat))
  assert mean_ms <. time_to_beat
}

fn list_mean(list: List(a), to_float: fn(a) -> Float) -> Float {
  let total =
    list.fold(over: list, from: 0.0, with: fn(acc, elem) {
      acc +. to_float(elem)
    })
  total /. int.to_float(list.length(list))
}
