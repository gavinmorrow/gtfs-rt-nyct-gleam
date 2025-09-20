import gleam/option

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

pub type TripReplacementPeriod {
  TripReplacementPeriod(
    /// The replacement period is for this route
    route_id: String,
    /// The start time is omitted, the end time is currently now + 30 minutes for
    /// all routes of the A division
    replacement_period: UnixTime,
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
    stop_time_update: List(StopTimeUpdate),
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
    timestampe: UnixTime,
    /// Identifies the current stop. The value must be the same as in stops.txt in
    /// the corresponding GTFS feed.
    stop_id: String,
  )
}

pub type TripDescriptor {
  TripDescriptor(
    trip_id: String,
    start_date: Date,
    route_id: String,
    nyct: NyctTripDescriptor,
  )
}

pub type NyctTripDescriptor {
  NyctTripDescriptor(train_id: option.Option(String), is_assigned: Bool)
}

/// Realtime update for arrival and/or departure events for a given stop on a
/// trip. Updates can be supplied for both past and future events.
/// The producer is allowed, although not required, to drop past events.
pub type StopTimeUpdate {
  StopTimeUpdate(
    arrival: StopTimeEvent,
    departure: StopTimeEvent,
    /// Must be the same as in stops.txt in the corresponding GTFS feed.
    stop_id: StopId,
    nyct: NyctStopTimeUpdate,
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

pub type VehicleStopStatus {
  /// The vehicle is just about to arrive at the stop (on a stop
  /// display, the vehicle symbol typically flashes).
  Incoming
  /// The vehicle is standing at the stop.
  Stopped
  /// The vehicle has departed and is in transit to the next stop.
  InTransit
}

pub type StopId =
  String

pub type Date {
  Date(year: Int, month: Int, day: Int)
}

/// POSIX/Unix time (ie number of seconds since January 1st 1970 00:00:00 UTC).
pub type UnixTime {
  UnixTime(Int)
}
