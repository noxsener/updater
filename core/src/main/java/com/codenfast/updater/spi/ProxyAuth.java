//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.spi;

/**
 * A service provider interface that handles the storage of proxy credentials.
 */
public interface ProxyAuth
{
    /** Credentials for a proxy server. */
    class Credentials {
        public final String username;
        public final String password;
        public Credentials (String username, String password) {
            this.username = username;
            this.password = password;
        }
    }

    /**
     * Loads the credentials for the app installed in {@code appDir}.
     */
    Credentials loadCredentials (String appDir);

    /**
     * Encrypts and saves the credentials for the app installed in {@code appDir}.
     */
    void saveCredentials (String appDir, String username, String password);
}
