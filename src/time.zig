const std = @import("std");
const buildopts = @import("buildopts");

extern fn getTimeUs() u32;

var firstTime = true;
var toff: i128 = 0;
pub fn getTimeUs_native() u32 {
    if (firstTime) {
        firstTime = false;
        toff = std.time.nanoTimestamp();
    }
    return @intCast(@mod(@divTrunc(std.time.nanoTimestamp() - toff, 1000), std.math.maxInt(u32)));
}

var startTime: u32 = 0;

pub fn initTime() void {
    if (buildopts.web) {
        startTime = getTimeUs();
    } else {
        startTime = getTimeUs_native();
    }
}

pub fn millis() u32 {
    if (buildopts.web) {
        return (getTimeUs() - startTime) / 1000;
    } else {
        return (getTimeUs_native() - startTime) / 1000;
    }
}


