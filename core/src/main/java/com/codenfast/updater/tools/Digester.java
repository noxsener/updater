//
// Updater - application installer, patcher and launcher
// Copyright (C) 2004-2018 Updater authors
// https://github.com/codenfast/updater/blob/master/LICENSE

package com.codenfast.updater.tools;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;

import java.security.GeneralSecurityException;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Signature;

import java.util.ArrayList;
import java.util.List;

import com.codenfast.updater.data.Application;
import com.codenfast.updater.data.Digest;
import com.codenfast.updater.data.EnvConfig;
import com.codenfast.updater.data.Resource;
import com.codenfast.updater.util.Base64;
import com.codenfast.updater.util.Config;

import static java.nio.charset.StandardCharsets.UTF_8;

/**
 * Handles the generation of the digest.txt file.
 */
public class Digester
{
    /**
     * A command line entry point for the digester.
     */
    public static void main (String[] args)
        throws IOException, GeneralSecurityException
    {
        switch (args.length) {
        case 1:
            createDigests(new File(args[0]), null, null, null);
            break;
        case 4:
            createDigests(new File(args[0]), new File(args[1]), args[2], args[3]);
            break;
        default:
            System.err.println("Usage: Digester app_dir [keystore_path password alias]");
            System.exit(255);
        }
    }

    /**
     * Creates digest file(s) and optionally signs them if {@code keystore} is not null.
     */
    public static void createDigests (File appdir, File keystore, String password, String alias)
        throws IOException, GeneralSecurityException
    {
        for (int version = 1; version <= Digest.VERSION; version++) {
            createDigest(version, appdir);
            if (keystore != null) {
                signDigest(version, appdir, keystore, password, alias);
            }
        }
    }

    /**
     * Creates a digest file in the specified application directory.
     */
    public static void createDigest (int version, File appdir)
        throws IOException
    {
        File target = new File(appdir, Digest.digestFile(version));
        System.out.println("Generating digest file '" + target + "'...");

        // create our application and instruct it to parse its business
        EnvConfig envc = new EnvConfig(appdir);
        Application app = new Application(envc);
        Config config = Application.readConfig(envc, false);
        app.initBase(config);
        app.initResources(config);

        List<Resource> rsrcs = new ArrayList<>();
        rsrcs.add(app.getConfigResource());
        rsrcs.addAll(app.getCodeResources());
        rsrcs.addAll(app.getResources());
        for (Application.AuxGroup ag : app.getAuxGroups()) {
            rsrcs.addAll(ag.codes);
            rsrcs.addAll(ag.rsrcs);
        }

        // reinit app just to verify that updater.txt has valid format
        app.init(true);

        // now generate the digest file
        Digest.createDigest(version, rsrcs, target);
    }

    /**
     * Creates a digest file in the specified application directory.
     */
    public static void signDigest (int version, File appdir,
                                   File storePath, String storePass, String storeAlias)
        throws IOException, GeneralSecurityException
    {
        String filename = Digest.digestFile(version);
        File inputFile = new File(appdir, filename);
        File signatureFile = new File(appdir, filename + Application.SIGNATURE_SUFFIX);

        try (FileInputStream storeInput = new FileInputStream(storePath);
             FileInputStream dataInput = new FileInputStream(inputFile);
             FileOutputStream signatureOutput = new FileOutputStream(signatureFile)) {

            // initialize the keystore
            KeyStore store = KeyStore.getInstance("JKS");
            store.load(storeInput, storePass.toCharArray());
            PrivateKey key = (PrivateKey)store.getKey(storeAlias, storePass.toCharArray());

            // sign the digest file
            String algo = Digest.sigAlgorithm(version);
            Signature sig = Signature.getInstance(algo);
            byte[] buffer = new byte[8192];
            int length;

            sig.initSign(key);
            while ((length = dataInput.read(buffer)) != -1) {
                sig.update(buffer, 0, length);
            }

            // Write out the signature
            String signed = Base64.encodeToString(sig.sign(), Base64.DEFAULT);
            signatureOutput.write(signed.getBytes(UTF_8));
        }
    }
}
