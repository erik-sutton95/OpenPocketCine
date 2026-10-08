// DJI protocol, wire and session sources (DUML, datalink, camera control/status, commands,
// feed watchdog, SoftAP, multicam discovery, media endpoints, DJI colour data) live in the
// OpenCineDJI package. Re-exported so app and facade call sites keep importing only this module.
@_exported import OpenCineDJI

/// This adapter names the DJI source; neutral Media ceilings take explicit calibration.
public typealias ScopeExposureCeiling = DJIScopeExposureCeiling
