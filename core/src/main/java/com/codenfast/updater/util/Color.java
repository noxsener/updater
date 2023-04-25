//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.util;

/**
 * Utilities for handling ARGB colors.
 */
public final class Color
{
    public static final int CLEAR = 0x00000000;
    public static final int WHITE = 0xFFFFFFFF;
    public static final int BLACK = 0xFF000000;

    public static float brightness (int argb) {
        // TODO: we're ignoring alpha here...
        int red = (argb >> 16) & 0xFF;
        int green = (argb >> 8) & 0xFF;
        int blue = (argb >> 0) & 0xFF;
        int max = Math.max(Math.max(red, green), blue);
        return ((float) max) / 255.0f;
    }

    private Color () {}
}
