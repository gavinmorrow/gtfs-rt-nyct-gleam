import gleam/dynamic/decode
import gleam/int
import gleam/option
import gleam/result
import gleam/string
import protobin

/// The contents of a feed message.
/// A feed is a continuous stream of feed messages. Each message in the stream is
/// obtained as a response to an appropriate HTTP GET request.
/// A realtime feed is always defined with relation to an existing GTFS feed.
/// All the entity ids are resolved with respect to the GTFS feed.
/// Note that "required" and "optional" as stated in this file refer to Protocol
/// Buffer cardinality, not semantic cardinality.  See reference.md at
/// https://github.com/google/transit/tree/master/gtfs-realtime for field
/// semantic cardinality.
pub type FeedMessage {
  FeedMessage(
    /// Metadata about this feed and feed message.
    header: FeedHeader,
    /// Contents of the feed.
    entity: List(FeedEntity),
  )
}

pub fn feed_message_decoder() -> decode.Decoder(FeedMessage) {
  use header <- decode.field(1, feed_header_bin_decoder())
  use entity <- decode.field(2, decode.list(of: feed_entity_bin_decoder()))
  decode.success(FeedMessage(header:, entity:))
}

/// Metadata about a feed, included in feed messages.
pub type FeedHeader {
  FeedHeader(
    /// Version of the feed specification.
    /// The current version is 2.0.  Valid versions are "2.0", "1.0".
    gtfs_realtime_version: String,
    /// This timestamp identifies the moment when the content of this feed has been
    /// created (in server time).
    timestamp: UnixTime,
    /// NYCT Subway extensions for the feed header
    nyct: NyctHeader,
  )
}

const feed_header_default = FeedHeader(
  gtfs_realtime_version: "1.0",
  timestamp: unix_time_default,
  nyct: nyct_header_default,
)

fn feed_header_decoder() -> decode.Decoder(FeedHeader) {
  use gtfs_realtime_version <- decode.field(1, protobin.decode_string())
  use timestamp <- decode.field(3, unix_time_decoder())
  use nyct <- decode.field(1001, nyct_header_bin_decoder())
  decode.success(FeedHeader(gtfs_realtime_version:, timestamp:, nyct:))
}

fn feed_header_bin_decoder() -> decode.Decoder(FeedHeader) {
  protobin.decode_protobuf(
    using: feed_header_decoder,
    named: "FeedHeader",
    default: feed_header_default,
  )
}

/// NYCT Subway extensions for the feed header
pub type NyctHeader {
  NyctHeader(
    /// Version of the NYCT Subway extensions
    /// The current version is 1.0
    version: String,
    /// For the NYCT Subway, the GTFS-realtime feed replaces any scheduled
    /// trip within the trip_replacement_period. 
    /// This feed is a full dataset, it contains all trips starting 
    /// in the trip_replacement_period. If a trip from the static GTFS is not
    /// found in the GTFS-realtime feed, it should be considered as cancelled.
    /// The replacement period can be different for each route, so here is 
    /// a list of the routes where the trips in the feed replace all 
    /// scheduled trips within the replacement period.
    trip_replacement_periods: List(TripReplacementPeriod),
  )
}

fn nyct_header_bin_decoder() -> decode.Decoder(NyctHeader) {
  use <-
    protobin.decode_protobuf(
      using: _,
      named: "NyctHeader",
      default: nyct_header_default,
    )

  use version <- decode.field(1, protobin.decode_string())
  use trip_replacement_periods <- decode.field(
    2,
    decode.list(of: trip_replacement_period_bin_decoder()),
  )
  decode.success(NyctHeader(version:, trip_replacement_periods:))
}

const nyct_header_default = NyctHeader(
  version: "1.0",
  trip_replacement_periods: [],
)

pub type TripReplacementPeriod {
  TripReplacementPeriod(
    /// The replacement period is for this route
    route_id: option.Option(String),
    /// The start time is omitted, the end time is currently now + 30 minutes for
    /// all routes of the A division
    replacement_period: UnixTime,
  )
}

const trip_replacement_period_default = TripReplacementPeriod(
  route_id: option.None,
  replacement_period: unix_time_default,
)

fn trip_replacement_period_decoder() -> decode.Decoder(TripReplacementPeriod) {
  use route_id <- decode.optional_field(
    1,
    option.None,
    protobin.decode_string() |> decode.map(option.Some),
  )
  use replacement_period <- decode.field(2, {
    use <-
      protobin.decode_protobuf(
        using: _,
        named: "ReplacementPeriod",
        default: unix_time_default,
      )
    use time <- decode.field(2, unix_time_decoder())
    time |> decode.success
  })
  decode.success(TripReplacementPeriod(route_id:, replacement_period:))
}

fn trip_replacement_period_bin_decoder() -> decode.Decoder(
  TripReplacementPeriod,
) {
  protobin.decode_protobuf(
    using: trip_replacement_period_decoder,
    named: "TripReplacementPeriod",
    default: trip_replacement_period_default,
  )
}

/// A definition (or update) of an entity in the transit feed.
pub type FeedEntity {
  FeedEntity(
    /// The ids are used only to provide incrementality support. The id should be
    /// unique within a FeedMessage. Consequent FeedMessages may contain
    /// FeedEntities with the same id. In case of a DIFFERENTIAL update the new
    /// FeedEntity with some id will replace the old FeedEntity with the same id
    /// (or delete it - see is_deleted below).
    /// The actual GTFS entities (e.g. stations, routes, trips) referenced by the
    /// feed must be specified by explicit selectors (see EntitySelector below for
    /// more info).
    id: String,
    data: FeedEntityData,
  )
}

const feed_entity_default = FeedEntity(id: "", data: feed_entity_data_default)

fn feed_entity_decoder() -> decode.Decoder(FeedEntity) {
  use id <- decode.field(1, protobin.decode_string())
  use data <- decode.then(feed_entity_data_decoder())
  decode.success(FeedEntity(id:, data:))
}

fn feed_entity_bin_decoder() {
  protobin.decode_protobuf(
    using: feed_entity_decoder,
    named: "FeedEntity",
    default: feed_entity_default,
  )
}

pub type FeedEntityData {
  /// Realtime update of the progress of a vehicle along a trip.
  /// Depending on the value of ScheduleRelationship, a TripUpdate can specify:
  /// - A trip that proceeds along the schedule.
  /// - A trip that proceeds along a route but has no fixed schedule.
  /// - A trip that have been added or removed with regard to schedule.
  ///
  /// The updates can be for future, predicted arrival/departure events, or for
  /// past events that already occurred.
  /// Normally, updates should get more precise and more certain (see
  /// uncertainty below) as the events gets closer to current time.
  /// Even if that is not possible, the information for past events should be
  /// precise and certain. In particular, if an update points to time in the past
  /// but its update's uncertainty is not 0, the client should conclude that the
  /// update is a (wrong) prediction and that the trip has not completed yet.
  ///
  /// Note that the update can describe a trip that is already completed.
  /// To this end, it is enough to provide an update for the last stop of the trip.
  /// If the time of that is in the past, the client will conclude from that that
  /// the whole trip is in the past (it is possible, although inconsequential, to
  /// also provide updates for preceding stops).
  /// This option is most relevant for a trip that has completed ahead of schedule,
  /// but according to the schedule, the trip is still proceeding at the current
  /// time. Removing the updates for this trip could make the client assume
  /// that the trip is still proceeding.
  /// Note that the feed provider is allowed, but not required, to purge past
  /// updates - this is one case where this would be practically useful.
  TripUpdate(
    /// The Trip that this message applies to. There can be at most one
    /// TripUpdate entity for each actual trip instance.
    /// If there is none, that means there is no prediction information available.
    /// It does *not* mean that the trip is progressing according to schedule.
    trip: TripDescriptor,
    /// Updates to StopTimes for the trip (both future, i.e., predictions, and in
    /// some cases, past ones, i.e., those that already happened).
    /// The updates must be sorted by stop_sequence, and apply for all the
    /// following stops of the trip up to the next specified one.
    ///
    /// Example 1:
    /// For a trip with 20 stops, a StopTimeUpdate with arrival delay and departure
    /// delay of 0 for stop_sequence of the current stop means that the trip is
    /// exactly on time.
    ///
    /// Example 2:
    /// For the same trip instance, 3 StopTimeUpdates are provided:
    /// - delay of 5 min for stop_sequence 3
    /// - delay of 1 min for stop_sequence 8
    /// - delay of unspecified duration for stop_sequence 10
    /// This will be interpreted as:
    /// - stop_sequences 3,4,5,6,7 have delay of 5 min.
    /// - stop_sequences 8,9 have delay of 1 min.
    /// - stop_sequences 10,... have unknown delay.
    stop_time_updates: List(StopTimeUpdate),
  )

  /// Realtime positioning information for a given vehicle.
  VehiclePosition(
    /// The Trip that this vehicle is serving.
    /// Can be empty or partial if the vehicle can not be identified with a given
    /// trip instance.
    trip: TripDescriptor,
    /// The stop sequence index of the current stop. The meaning of
    /// current_stop_sequence (i.e., the stop that it refers to) is determined by
    /// current_status.
    /// If current_status is missing IN_TRANSIT_TO is assumed.
    current_stop_sequence: Int,
    current_status: VehicleStopStatus,
    timestamp: UnixTime,
    /// Identifies the current stop. The value must be the same as in stops.txt in
    /// the corresponding GTFS feed.
    stop_id: String,
  )
}

const feed_entity_data_default = trip_update_default

const trip_update_default = TripUpdate(
  trip: trip_descriptor_default,
  stop_time_updates: [],
)

const vehicle_position_default = VehiclePosition(
  trip: trip_descriptor_default,
  current_stop_sequence: 0,
  current_status: vehicle_stop_status_default,
  timestamp: unix_time_default,
  stop_id: "",
)

fn feed_entity_data_decoder() -> decode.Decoder(FeedEntityData) {
  let trip_update_decoder =
    decode.field(3, trip_update_bin_decoder(), decode.success)

  let vehicle_position_decoder =
    decode.field(4, vehicle_position_bin_decoder(), decode.success)

  decode.one_of(trip_update_decoder, or: [vehicle_position_decoder])
}

fn trip_update_bin_decoder() -> decode.Decoder(FeedEntityData) {
  use <-
    protobin.decode_protobuf(
      using: _,
      named: "TripUpdate",
      default: trip_update_default,
    )
  use trip <- decode.field(1, trip_descriptor_bin_decoder())
  use stop_time_updates <- decode.field(
    2,
    decode.list(of: stop_time_update_bin_decoder()),
  )
  TripUpdate(trip:, stop_time_updates:) |> decode.success
}

fn vehicle_position_bin_decoder() -> decode.Decoder(FeedEntityData) {
  use <-
    protobin.decode_protobuf(
      using: _,
      named: "VehiclePosition",
      default: vehicle_position_default,
    )

  use trip <- decode.field(1, trip_descriptor_bin_decoder())
  use current_stop_sequence <- decode.field(3, protobin.decode_uint())
  use current_status <- decode.optional_field(
    4,
    InTransit,
    vehicle_stop_status_decoder(),
  )
  use timestamp <- decode.field(5, unix_time_decoder())
  use stop_id <- decode.field(7, protobin.decode_string())

  VehiclePosition(
    trip:,
    current_stop_sequence:,
    current_status:,
    timestamp:,
    stop_id:,
  )
  |> decode.success
}

pub type TripDescriptor {
  TripDescriptor(
    trip_id: String,
    start_date: Date,
    route_id: String,
    nyct: NyctTripDescriptor,
  )
}

const trip_descriptor_default = TripDescriptor(
  trip_id: "",
  start_date: date_default,
  route_id: "",
  nyct: nyct_trip_descriptor_default,
)

fn trip_descriptor_decoder() -> decode.Decoder(TripDescriptor) {
  use trip_id <- decode.field(1, protobin.decode_string())
  use start_date <- decode.field(3, date_decoder())
  use route_id <- decode.field(5, protobin.decode_string())
  use nyct <- decode.field(1001, nyct_trip_descriptor_bin_decoder())
  decode.success(TripDescriptor(trip_id:, start_date:, route_id:, nyct:))
}

fn trip_descriptor_bin_decoder() -> decode.Decoder(TripDescriptor) {
  protobin.decode_protobuf(
    using: trip_descriptor_decoder,
    named: "TripDescriptor",
    default: trip_descriptor_default,
  )
}

pub type NyctTripDescriptor {
  NyctTripDescriptor(
    /// The nyct_train_id is meant for internal use only. It provides an
    /// easy way to associated GTFS-realtime trip identifiers with NYCT rail
    /// operations identifier 
    /// 
    /// The ATS office system assigns unique train identification (Train ID) to
    /// each train operating within or ready to enter the mainline of the
    /// monitored territory. An example of this is 06 0123+ PEL/BBR and is decoded
    /// as follows: 
    /// 
    /// The first character represents the trip type designator. 0 identifies a
    /// scheduled revenue trip. Other revenue trip values that are a result of a
    /// change to the base schedule include; [= reroute], [/ skip stop], [$ turn
    /// train] also known as shortly lined service.  
    /// 
    /// The second character 6 represents the trip line i.e. number 6 train The
    /// third set of characters identify the decoded origin time. The last
    /// character may be blank "on the whole minute" or + "30 seconds" 
    /// 
    /// Note: Origin times will not change when there is a trip type change.  This
    /// is followed by a three character "Origin Location" / "Destination
    /// Location"
    train_id: option.Option(String),
    /// This trip has been assigned to a physical train. If true, this trip is
    /// already underway or most likely will depart shortly. 
    ///
    /// Train Assignment is a function of the Automatic Train Supervision (ATS)
    /// office system used by NYCT Rail Operations to monitor and track train
    /// movements. ATS provides the ability to "assign" the nyct_train_id
    /// attribute when a physical train is at its origin terminal. These assigned
    /// trips have the is_assigned field set in the TripDescriptor.
    ///
    /// When a train is at a terminal but has not been given a work program it is
    /// declared unassigned and is tagged as such. Unassigned trains can be moved
    /// to a storage location or assigned a nyct_train_id when a determination for
    /// service is made.
    is_assigned: Bool,
  )
}

const nyct_trip_descriptor_default = NyctTripDescriptor(
  train_id: option.None,
  is_assigned: False,
)

fn nyct_trip_descriptor_bin_decoder() -> decode.Decoder(NyctTripDescriptor) {
  use <-
    protobin.decode_protobuf(
      using: _,
      named: "NyctTripDescriptor",
      default: nyct_trip_descriptor_default,
    )

  use train_id <- decode.optional_field(
    1,
    option.None,
    protobin.decode_string() |> decode.map(option.Some),
  )
  use is_assigned <- decode.optional_field(2, False, protobin.decode_bool())

  NyctTripDescriptor(train_id:, is_assigned:) |> decode.success
}

/// Realtime update for arrival and/or departure events for a given stop on a
/// trip. Updates can be supplied for both past and future events.
/// The producer is allowed, although not required, to drop past events.
pub type StopTimeUpdate {
  StopTimeUpdate(
    arrival: option.Option(StopTimeEvent),
    departure: option.Option(StopTimeEvent),
    /// Must be the same as in stops.txt in the corresponding GTFS feed.
    stop_id: StopId,
    nyct: NyctStopTimeUpdate,
  )
}

const stop_time_update_default = StopTimeUpdate(
  arrival: option.Some(stop_time_event_default),
  departure: option.Some(stop_time_event_default),
  stop_id: stop_id_default,
  nyct: nyct_stop_time_update_default,
)

fn stop_time_update_decoder() -> decode.Decoder(StopTimeUpdate) {
  use arrival <- decode.optional_field(
    2,
    option.None,
    stop_time_event_bin_decoder() |> decode.map(option.Some),
  )
  use departure <- decode.optional_field(
    3,
    option.None,
    stop_time_event_bin_decoder() |> decode.map(option.Some),
  )
  use stop_id <- decode.field(4, protobin.decode_string())
  use nyct <- decode.field(1001, nyct_stop_time_bin_decoder())
  decode.success(StopTimeUpdate(arrival:, departure:, stop_id:, nyct:))
}

fn stop_time_update_bin_decoder() {
  protobin.decode_protobuf(
    using: stop_time_update_decoder,
    named: "StopTimeUpdate",
    default: stop_time_update_default,
  )
}

/// NYCT Subway extensions for the stop time update
pub type NyctStopTimeUpdate {
  NyctStopTimeUpdate(
    /// Provides the planned station arrival track. The following is the Manhattan
    /// track configurations:
    /// 1: southbound local
    /// 2: southbound express
    /// 3: northbound express
    /// 4: northbound local
    ///
    /// In the Bronx (except Dyre Ave line)
    /// M: bi-directional express (in the AM express to Manhattan, in the PM
    /// express away).
    ///
    /// The Dyre Ave line is configured:
    /// 1: southbound
    /// 2: northbound
    /// 3: bi-directional
    scheduled_track: option.Option(String),
    /// This is the actual track that the train is operating on and can be used to
    /// determine if a train is operating according to its current schedule
    /// (plan).
    /// 
    /// The actual track is known only shortly before the train reaches a station,
    /// typically not before it leaves the previous station. Therefore, the NYCT
    /// feed sets this field only for the first station of the remaining trip.
    /// 
    /// Different actual and scheduled track is the result of manually rerouting a
    /// train off it scheduled path.  When this occurs, prediction data may become
    /// unreliable since the train is no longer operating in accordance to its
    /// schedule.  The rules engine for the 'countdown' clocks will remove this
    /// train from all schedule stations.
    actual_track: option.Option(String),
  )
}

const nyct_stop_time_update_default = NyctStopTimeUpdate(
  scheduled_track: option.None,
  actual_track: option.None,
)

fn nyct_stop_time_bin_decoder() -> decode.Decoder(NyctStopTimeUpdate) {
  use <-
    protobin.decode_protobuf(
      using: _,
      named: "NyctStopTimeUpdate",
      default: nyct_stop_time_update_default,
    )

  use scheduled_track <- decode.optional_field(
    1,
    option.None,
    protobin.decode_string() |> decode.map(option.Some),
  )
  use actual_track <- decode.optional_field(
    2,
    option.None,
    protobin.decode_string() |> decode.map(option.Some),
  )
  NyctStopTimeUpdate(scheduled_track:, actual_track:) |> decode.success
}

/// Timing information for a single predicted event (either arrival or
/// departure).
/// Timing consists of delay and/or estimated time, and uncertainty.
/// - delay should be used when the prediction is given relative to some
///   existing schedule in GTFS.
/// - time should be given whether there is a predicted schedule or not. If
///   both time and delay are specified, time will take precedence
///   (although normally, time, if given for a scheduled trip, should be
///   equal to scheduled time in GTFS + delay).
///
/// Uncertainty applies equally to both time and delay.
/// The uncertainty roughly specifies the expected error in true delay (but
/// note, we don't yet define its precise statistical meaning). It's possible
/// for the uncertainty to be 0, for example for trains that are driven under
/// computer timing control.
pub type StopTimeEvent {
  StopTimeEvent(
    /// Event as absolute time.
    time: UnixTime,
  )
}

const stop_time_event_default = StopTimeEvent(time: unix_time_default)

fn stop_time_event_decoder() -> decode.Decoder(StopTimeEvent) {
  use time <- decode.field(2, unix_time_decoder())
  StopTimeEvent(time:) |> decode.success
}

fn stop_time_event_bin_decoder() -> decode.Decoder(StopTimeEvent) {
  protobin.decode_protobuf(
    using: stop_time_event_decoder,
    named: "StopTimeEvent",
    default: stop_time_event_default,
  )
}

pub type VehicleStopStatus {
  /// The vehicle is just about to arrive at the stop (on a stop
  /// display, the vehicle symbol typically flashes).
  Incoming
  /// The vehicle is standing at the stop.
  Stopped
  /// The vehicle has departed and is in transit to the next stop.
  InTransit
}

const vehicle_stop_status_default = InTransit

fn vehicle_stop_status_decoder() -> decode.Decoder(VehicleStopStatus) {
  use variant <- decode.then(protobin.decode_uint())
  case variant {
    0 -> Incoming |> decode.success
    1 -> Stopped |> decode.success
    2 -> InTransit |> decode.success
    _ -> decode.failure(vehicle_stop_status_default, "VehicleStopStatus")
  }
}

pub type StopId =
  String

const stop_id_default = ""

pub type Date {
  Date(year: Int, month: Int, day: Int)
}

const date_default = Date(year: 1970, month: 1, day: 1)

fn date_decoder() -> decode.Decoder(Date) {
  use date <- decode.then(protobin.decode_string())
  let date = {
    use year <- result.try(
      date
      |> string.slice(at_index: 0, length: 4)
      |> int.parse,
    )
    use month <- result.try(
      date |> string.slice(at_index: 4, length: 2) |> int.parse,
    )
    use day <- result.try(
      date |> string.slice(at_index: 6, length: 2) |> int.parse,
    )
    Date(year:, month:, day:) |> Ok
  }
  case date {
    Ok(date) -> decode.success(date)
    Error(Nil) -> decode.failure(date_default, "Date")
  }
}

/// POSIX/Unix time (ie number of seconds since January 1st 1970 00:00:00 UTC).
pub type UnixTime {
  UnixTime(Int)
}

const unix_time_default = UnixTime(0)

fn unix_time_decoder() -> decode.Decoder(UnixTime) {
  use seconds <- decode.then(protobin.decode_uint())
  UnixTime(seconds) |> decode.success
}
