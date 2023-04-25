//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.util;

import org.junit.Test;

import static com.codenfast.updater.util.StringUtil.couldBeValidUrl;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * Tests {@link StringUtil}.
 */
public class StringUtilTest
{
    @Test public void testCouldBeValidUrl ()
    {
        assertTrue(couldBeValidUrl("http://www.foo.com/"));
        assertTrue(couldBeValidUrl("http://www.foo.com/A-B-C/1_2_3/~bar/q.jsp?x=u+i&y=2;3;4#baz%20baz"));
        assertTrue(couldBeValidUrl("https://user:secret@www.foo.com/"));

        assertFalse(couldBeValidUrl("http://www.foo.com & echo hello"));
        assertFalse(couldBeValidUrl("http://www.foo.com\""));
    }
}
