//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.data;

/**
 * System property constants associated with Updater.
 */
public class Properties
{
    /** This property will be set to "true" on the application when it is being run by updater. */
    public static final String UPDATER = "com.codenfast.updater";

    /** If accepting connections from the launched application, this property
     * will be set to the connection server port. */
    public static final String CONNECT_PORT = "com.codenfast.updater.connectPort";
}
