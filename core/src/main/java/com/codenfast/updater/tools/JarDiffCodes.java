//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.tools;

/**
 * Constants shared by {@link JarDiff} and {@link JarDiffPatcher}.
 */
public interface JarDiffCodes
{
    /** The name of the jardiff control file. */
    String INDEX_NAME = "META-INF/INDEX.JD";

    /** The version header used in the control file. */
    String VERSION_HEADER = "version 1.0";

    /** A jardiff command to remove an entry. */
    String REMOVE_COMMAND = "remove";

    /** A jardiff command to move an entry. */
    String MOVE_COMMAND = "move";
}
