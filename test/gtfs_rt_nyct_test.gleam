import gleam/list
import gleeunit
import gtfs_rt_nyct
import protobin
import simplifile as file

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn gtfs_rt_full_test() -> Nil {
  let path = "./test/gtfs-rt-nyct.pb"
  let assert Ok(bits) = file.read_bits(from: path)
  let assert Ok(protobin.Parsed(value: gtfs, ..)) =
    protobin.parse_with_config(
      from: bits,
      using: gtfs_rt_nyct.feed_message_decoder(),
      config: protobin.Config(ignore_groups: False),
    )

  assert gtfs.header.gtfs_realtime_version == "1.0"
  assert gtfs.entity |> list.length == 445
}
