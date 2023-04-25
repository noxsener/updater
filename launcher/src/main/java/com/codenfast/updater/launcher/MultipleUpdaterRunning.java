//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.launcher;

import java.io.IOException;

/**
 * Thrown when it's detected that multiple instances of the same updater installer are running.
 */
public class MultipleUpdaterRunning extends IOException
{
    public MultipleUpdaterRunning ()
    {
        super("m.another_updater_running");
    }

}
