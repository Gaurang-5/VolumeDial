@import Foundation;
#include "i2c.h"
#include <assert.h>

static void checksum(UInt8 *reply) {
    reply[10] = 0x50;
    for (int i = 0; i < 10; i++) reply[10] ^= reply[i];
}

int main(void) {
    UInt8 reply[11] = {0x6e, 0x88, 0x02, 0, VOLUME, 0, 0, 50, 0, 28, 0};
    checksum(reply);
    DDCValue valid = convertI2CtoDDC((char *)reply);
    assert(valid.curValue == 28 && valid.maxValue == 50);

    // A damaged current-value byte must not become a plausible new volume.
    reply[9] = 10;
    assert(convertI2CtoDDC((char *)reply).curValue == -1);

    // Successful I2C transport can still return an empty or unsupported reply.
    UInt8 empty[11] = {0};
    assert(convertI2CtoDDC((char *)empty).curValue == -1);
    reply[3] = 1;
    checksum(reply);
    assert(convertI2CtoDDC((char *)reply).curValue == -1);

    reply[3] = 0;
    reply[2] = 0x01;
    checksum(reply);
    assert(convertI2CtoDDC((char *)reply).curValue == -1);

    reply[2] = 0x02;
    reply[9] = 0;
    checksum(reply);
    assert(convertI2CtoDDC((char *)reply).curValue == 0);
    puts("PASS: valid volume, damaged reply, empty reply, unsupported reply, wrong command, true zero");
}
