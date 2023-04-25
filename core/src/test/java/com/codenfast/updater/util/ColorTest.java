//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.util;

import org.junit.Test;
import static org.junit.Assert.assertEquals;

/**
 * Tests {@link Color}.
 */
public class ColorTest
{
    @Test
    public void testBrightness() {
        assertEquals(0, Color.brightness(0xFF000000), 0.0000001);
        assertEquals(1, Color.brightness(0xFFFFFFFF), 0.0000001);
        assertEquals(0.0117647, Color.brightness(0xFF010203), 0.0000001);
        assertEquals(1, Color.brightness(0xFF00FFC8), 0.0000001);
    }
}
