const std = @import("std");

var count_ms:u32 = 0;

pub fn advance(delta: u32) void {
    count_ms += delta;
}

pub fn millis() u32 {
    return count_ms;
}

