//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.util;

/**
 * Used to communicate progress.
 */
public interface ProgressObserver
{
    /**
     * Informs the observer that we have completed the specified
     * percentage of the process.
     */
    void progress (int percent);
}
