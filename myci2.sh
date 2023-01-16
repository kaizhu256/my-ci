#!/bin/sh

# sh one-liner
# (curl -o /tmp/myci2.sh -s https://raw.githubusercontent.com/kaizhu256/myci2/alpha/myci2.sh && . /tmp/myci2.sh && shMyciInit force)
# shMyciUpdate
# shSecretFileSet ~/.ssh/known_hosts .ssh/known_hosts
# shSecretGitCommitAndPush

shCiPreMyci() {(set -e
# this function will run pre-ci
    if (printf "$GITHUB_REF_NAME" | grep -q ".*/.*/.*")
    then
        shGithubCheckoutRemote "$GITHUB_REF_NAME"
        return
    fi
    if [ "$GITHUB_REF_NAME" = shell ]
    then
        if (! shCiIsMainJob)
        then
            return
        fi
        shGithubFileDownload kaizhu256/mysecret2/alpha/.mysecret2.json.encrypted
        shSshReverseTunnelServer
    fi
)}

shCryptoJweDecryptEncrypt() {(set -e
# this function will decrypt/encrypt file using jwe and $MY_GITHUB_TOKEN
# example use:
# shCryptoJweDecryptEncrypt decrypt .mysecret2.json.encrypted .mysecret2.json
# shCryptoJweDecryptEncrypt encrypt .mysecret2.json
# shGitLsTree | sort -rk4 # sort by size
    shGithubTokenExport
    node --input-type=module --eval '
import assert from "assert";
import moduleFs from "fs";
import {
    webcrypto
} from "crypto";

let {
    MY_GITHUB_TOKEN
} = process.env;

async function cryptoJweDecrypt({
    fileDecrypted,
    fileEncrypted,
    mockResult
}) {

// This function will:
// 1. Parse 256-bit jwk-formatted key-encryption-key <jwkKek>
// 2. Key-unwrap 256-bit content-encryption-key (cek) in <jweCompact>
//    using <jwkKek>.
// 3. Decrypt ciphertext with cek, iv, tag in <jweCompact>

    let cek;
    let header;
    let iv;
    let jweCompact;
    let jwkKek;
    let kek;
    let plaintext;
    let tag;
    function base64urlFromBuffer(buf) {
        return Buffer.from(buf).toString("base64").replace((
            /\+/g
        ), "-").replace((
            /\//g
        ), "_").replace((
            /\=/g
        ), "");
    }
    if (mockResult) {
        return mockResult;
    }

// 1. Parse 256-bit jwk-formatted key-encryption-key <jwkKek>

    jwkKek = await webcrypto.subtle.digest("SHA-256", MY_GITHUB_TOKEN);
    jwkKek = JSON.stringify({
        k: base64urlFromBuffer(jwkKek),
        kty: "oct"
    });
    jwkKek = JSON.parse(jwkKek);

// 2. Key-unwrap 256-bit content-encryption-key (cek) in <jweCompact>
//    using <jwkKek>.

    jweCompact = await moduleFs.promises.readFile(fileEncrypted, "utf8");
    jweCompact = jweCompact.replace((
        /\s/g
    ), "");
    [
        header,
        cek,
        iv,
        plaintext,
        tag
    ] = jweCompact.replace((
        /-/g
    ), "+").replace((
        /_/g
    ), "/").split(".").map(function (elem) {
        return Buffer.from(elem, "base64");
    });
    header = jweCompact.split(".")[0];
    assert(
        "eyJhbGciOiJBMjU2S1ciLCJlbmMiOiJBMjU2R0NNIn0" === header,
        `cryptoJweDecrypt - invalid header - ${header}`
    );
    kek = await webcrypto.subtle.importKey(
        "jwk",
        jwkKek,
        {
            length: 256,
            name: "AES-KW"
        },
        true,
        [
            "unwrapKey", "wrapKey"
        ]
    );
    cek = await webcrypto.subtle.unwrapKey(
        "raw",
        cek,
        kek,
        "AES-KW",
        "AES-GCM",
        true,
        [
            "decrypt", "encrypt"
        ]
    );

// 3. Decrypt ciphertext with cek, iv, tag in <jweCompact>

    plaintext = await webcrypto.subtle.decrypt(
        {
            additionalData: header,
            iv,
            name: "AES-GCM",
            tagLength: 128
        },
        cek,
        Buffer.concat([
            plaintext, tag
        ])
    );
    plaintext = new TextDecoder().decode(plaintext);
    if (fileDecrypted) {
        await moduleFs.promises.writeFile(fileDecrypted, plaintext);
    }
    return plaintext;
}

async function cryptoJweEncrypt({
    fileDecrypted
}) {

// This function will:
// 1. Parse 256-bit jwk-formatted key-encryption-key <jwkKek>
// 2. Create random 256-bit content-encryption-key (cek).
// 3. Key-wrap cek with given <jwkKek>.
// 4. Read plaintext from <fileDecrypted>.
// 5. Encrypt plaintext with cek.
// 6. Save all of above as jwe-compact-format to <fileDecrypted>.encrypted
//
// BASE64URL(UTF8(JWE Protected Header)) || . ||
// BASE64URL(JWE Encrypted Key) || . ||
// BASE64URL(JWE Initialization Vector) || . ||
// BASE64URL(JWE Ciphertext) || . ||
// BASE64URL(JWE Authentication Tag)

    let cek;
    let ciphertext;
    let header;
    let iv;
    let jweCompact = [];
    let jwkKek;
    let kek;
    let tag;
    function base64urlFromBuffer(buf) {
        return Buffer.from(buf).toString("base64").replace((
            /\+/g
        ), "-").replace((
            /\//g
        ), "_").replace((
            /\=/g
        ), "");
    }

// BASE64URL(UTF8(JWE Protected Header)) || . ||

    header = base64urlFromBuffer(JSON.stringify({
        alg: "A256KW",
        enc: "A256GCM"
    }));
    jweCompact.push(header);

// Use given jwkKek or read from file.

    jwkKek = await webcrypto.subtle.digest("SHA-256", MY_GITHUB_TOKEN);
    jwkKek = JSON.stringify({
        k: base64urlFromBuffer(jwkKek),
        kty: "oct"
    });

// 1. Parse 256-bit jwk-formatted key-encryption-key <jwkKek>

    jwkKek = JSON.parse(jwkKek);
    kek = await webcrypto.subtle.importKey(
        "jwk",
        jwkKek,
        {
            length: 256,
            name: "AES-KW"
        },
        true,
        [
            "unwrapKey", "wrapKey"
        ]
    );
    jwkKek = JSON.stringify({
        k: jwkKek.k,
        kty: jwkKek.kty
    });

// 2. Create random 256-bit content-encryption-key (cek).

    cek = await webcrypto.subtle.generateKey(
        {
            length: 128,
            name: "AES-GCM"
        },
        true,
        [
            "decrypt", "encrypt"
        ]
    );

// 3. Key-wrap cek with given <jwkKek>.

    jweCompact.push(base64urlFromBuffer(
        await webcrypto.subtle.wrapKey("raw", cek, kek, "AES-KW")
    ));

// 4. Read plaintext from <fileDecrypted>.

    ciphertext = await moduleFs.promises.readFile(fileDecrypted);

// 5. Encrypt plaintext with cek.

    iv = webcrypto.getRandomValues(new Uint8Array(12));
    jweCompact.push(base64urlFromBuffer(iv));
    ciphertext = await webcrypto.subtle.encrypt(
        {
            additionalData: header,
            iv,
            name: "AES-GCM",
            tagLength: 128
        },
        cek,
        ciphertext
    );

// 6. Save all of above as jwe-compact-format to <fileDecrypted>.encrypted

    ciphertext = Buffer.from(ciphertext);
    tag = ciphertext.slice(-16);
    ciphertext = ciphertext.slice(0, -16);
    jweCompact.push(base64urlFromBuffer(ciphertext).replace((
        /.{72}/g
    ), "$&\n"));
    jweCompact.push(base64urlFromBuffer(tag));
    jweCompact = jweCompact.join("\n.\n");
    await moduleFs.promises.writeFile(
        fileDecrypted + ".encrypted",
        jweCompact + "\n"
    );
    return jweCompact;
}

(async function () {
    if (process.argv[1] === "decrypt") {
        await cryptoJweDecrypt({
            fileDecrypted: process.argv[3],
            fileEncrypted: process.argv[2]
        });
    } else {
        await cryptoJweEncrypt({
            fileDecrypted: process.argv[2]
        });
    }
}());
' "$@" # '
)}

shGithubCheckoutRemote() {(set -e
# this function will run like actions/checkout, except checkout remote-branch
    # GITHUB_REF_NAME="owner/repo/branch"
    export GITHUB_REF_NAME="$1"
    local FILE
    if (printf "$GITHUB_REF_NAME" | grep -q ".*/.*/.*")
    then
        # branch - */*/*
        git fetch origin alpha
        # assert latest ci
        if [ "$(git rev-parse "$GITHUB_REF_NAME")" \
            != "$(git rev-parse origin/alpha)" ]
        then
            git push -f origin "origin/alpha:$GITHUB_REF_NAME"
            shGithubWorkflowDispatch "$GITHUB_REPOSITORY" "$GITHUB_REF_NAME"
            return 1
        fi
    else
        # branch - alpha, beta, master
        export GITHUB_REF_NAME="$GITHUB_REPOSITORY/$GITHUB_REF_NAME"
    fi
    export GITHUB_REPOSITORY="$(printf "$GITHUB_REF_NAME" | cut -d'/' -f1,2)"
    export GITHUB_REF_NAME="$(printf "$GITHUB_REF_NAME" | cut -d'/' -f3)"
    (set -e
    cd ..
    shGitCmdWithGithubToken clone \
        "https://github.com/$GITHUB_REPOSITORY" \
        "$GITHUB_WORKSPACE.tmp" \
        --branch="$GITHUB_REF_NAME" \
        --depth=1 \
        --single-branch
    rm -rf "$GITHUB_WORKSPACE/"* "$GITHUB_WORKSPACE/".* || true
    cp -rf "$GITHUB_WORKSPACE.tmp/"* "$GITHUB_WORKSPACE/"
    cp -rf "$GITHUB_WORKSPACE.tmp/".* "$GITHUB_WORKSPACE/" || true
    cd "$GITHUB_WORKSPACE"
    )
    cp .gitconfig .git/config
    git reset "origin/$GITHUB_REF_NAME" --hard
    # fetch jslint_ci.sh from trusted source
    for FILE in .ci.sh jslint_ci.sh
    do
        shGithubFileDownload "$GITHUB_REPOSITORY/alpha/$FILE"
    done
)}

shMyciInit() {(set -e
# this function will init myci2 in current environment
    local FILE
    local MODE_FORCE
    if [ "$1" = force ]
    then
        MODE_FORCE=1
        shift
    fi
    cd "$HOME"
    # init jslint_ci.sh
    for FILE in .screenrc .vimrc jslint_ci.sh
    do
        if [ ! -f "$FILE" ] || [ "$MODE_FORCE" ]
        then
            curl -s -o "$FILE" \
"https://raw.githubusercontent.com/kaizhu256/myci2/alpha/$FILE"
        fi
    done
    # init myci2
    if (git --version >/dev/null 2>&1)
    then
        if [ ! -d myci2 ] || [ "$MODE_FORCE" ]
        then
            rm -rf myci2
            git clone https://github.com/kaizhu256/myci2 \
                --branch=alpha --single-branch
            shMyciUpdate
        fi
    fi
    # init .bashrc
    if [ ! -f .bashrc ]
    then
        touch .bashrc
    fi
    for FILE in jslint_ci.sh myci2/myci2.sh
    do
        if [ -f "$FILE" ] && ! (grep -q "^. ~/$FILE$" .bashrc)
        then
            printf "\n. ~/$FILE\n" >> .bashrc
        fi
    done
)}

shMyciUpdate() {(set -e
# this function will update myci2 in current dir
    if [ ! -d .git ]
    then
        return
    fi
    local FILE
    local FILE_MYCI
    local FILE_HOME
    # ln file
    mkdir -p "$HOME/.vim"
    for FILE in \
        .vimrc \
        jslint.mjs \
        jslint_ci.sh \
        jslint_wrapper_vim.vim \
        myci2.sh
    do
        FILE_MYCI="$HOME/myci2/$FILE"
        FILE_HOME="$HOME/$FILE"
        case "$FILE" in
        jslint_wrapper_vim.vim)
            FILE_HOME="$HOME/.vim/$FILE"
            ;;
        esac
        if [ -f "$FILE_HOME" ]
        then
            ln -f "$FILE_HOME" "$FILE_MYCI"
        else
            ln -f "$FILE_MYCI" "$FILE_HOME"
        fi
        if [ -f "$FILE" ] && [ "$PWD" != "$HOME/myci2" ]
        then
            ln -f "$FILE_MYCI" "$FILE" || true
        fi
    done
    ln -f "$HOME/jslint.mjs" "$HOME/.vim/jslint.mjs"
    # detect nodejs
    if ! ( node --version >/dev/null 2>&1 \
        || node.exe --version >/dev/null 2>&1)
    then
        git --no-pager diff
        return
    fi
    # sync .gitignore
    if [ ! -f .gitignore ]
    then
        touch .gitignore
    fi
    node --eval '
(async function () {
    let data1;
    let data2;
    let file1 = process.argv[1];
    let file2 = process.argv[2];
    let moduleFs = require("fs");
    data1 = await moduleFs.promises.readFile(file1, "utf8");
    data2 = await moduleFs.promises.readFile(file2, "utf8");
    data2 = data2.replace((
        /[\S\s]*?\n# jslint .gitignore end\n|^/m
    ), data1.replace((
        /\$/g
    ), "$$"));
    await moduleFs.promises.writeFile(file2, data2);
}());
' "$HOME/myci2/.gitignore" .gitignore # '
    #
    git --no-pager diff
)}

shSecretCryptoDecrypt() {(set -e
# this function will decrypt file using jwe and $MY_GITHUB_TOKEN
    shCryptoJweDecryptEncrypt decrypt .mysecret2.json.encrypted .mysecret2.json
    chmod 600 .mysecret2.json
)}

shSecretCryptoEncrypt() {(set -e
# this function will encrypt file using jwe and $MY_GITHUB_TOKEN
    shCryptoJweDecryptEncrypt encrypt .mysecret2.json
)}

shSecretFileGet() {(set -e
# this function will open json-file, and write file-key $1 to file $2
    node --input-type=module --eval '
import moduleFs from "fs";
import modulePath from "path";
async function fsWriteFileWithParents(pathname, data) {

// This function will write <data> to <pathname> and lazy-mkdirp if necessary.

    // await moduleFsInit();

// Try writing to pathname.

    try {
        await moduleFs.promises.writeFile(pathname, data);
    } catch (ignore) {

// Lazy mkdirp.

        await moduleFs.promises.mkdir(modulePath.dirname(pathname), {
            recursive: true
        });

// Retry writing to pathname.

        await moduleFs.promises.writeFile(pathname, data);
    }
    // console.error("wrote file " + pathname);
}
(async function () {
    let data;
    let fileSecret = ".mysecret2.json";
    let fileKey;
    let fileWrite;
    fileKey = process.argv[1];
    fileWrite = process.argv[2];
    data = JSON.parse(
        await moduleFs.promises.readFile(fileSecret)
    );
    data = Buffer.from(data[fileKey], "base64");
    await fsWriteFileWithParents(fileWrite, data);
    await moduleFs.promises.chmod(fileWrite, "600");
}());
' "$@" # '
)}

shSecretFileSet() {(set -e
# this function will open json-file, and set file $1 to key $2
    node --input-type=module --eval '
import moduleFs from "fs";
(async function () {
    let data;
    let file = process.argv[1];
    let key = process.argv[2];
    let fileSecret = `${process.env.HOME}/mysecret2/.mysecret2.json`;
    data = JSON.parse(
        await moduleFs.promises.readFile(fileSecret)
    );
    data[key] = Buffer.from(
        await moduleFs.promises.readFile(file)
    ).toString("base64");
    await moduleFs.promises.writeFile(
        fileSecret,
        JSON.stringify(data, undefined, 4) + "\n"
    );
}());
' "$@" # '
)}

shSecretGitCommitAndPush() {(set -e
# this function will git-commit and git-push mysecret2
    cd "$HOME/mysecret2/"
    shJsonNormalize .mysecret2.json
    shSecretCryptoEncrypt
    git commit -am 'update .mysecret2.json.encrypted'
    git push
)}

shSecretVarExport() {
# this function will open json-file, and export env key/val items
    eval "$(node --input-type=module --eval '
import moduleFs from "fs";
(async function () {
    let data;
    data = JSON.parse(
        await moduleFs.promises.readFile(".mysecret2.json")
    );
    data = Object.entries(data);
    data = data.filter(function ([
        key
    ]) {
        return key.startsWith("EXPORT.");
    });
    data = data.map(function ([
        key, val
    ]) {
        return (
            "export "
            + key.replace("EXPORT.", "")
            + "="
            + "\u0027"
            + val.replace((
                /\u0027/g
            ), `\u0027"\u0027"\u0027`)
            + "\u0027\n"
        );
    }).join("");
    console.log(data);
}());
' "$@")" # '
}

shSshCryptoDecrypt() {(set -e
# this function will decrypt ssh-files to dir .ssh/
    for FILE in authorized_keys id_ed25519 known_hosts
    do
        shSecretFileGet ".ssh/$FILE" "$HOME/.ssh/$FILE"
    done
)}

shSshKeygen() {(set -e
# this function will generate generic ssh key
    local FILE
    cd ~/.ssh/
    rm -f id_ed25519
    rm -f id_ed25519.pub
    ssh-keygen \
        -C "your_email@example.com" \
        -N "" \
        -f ~/.ssh/id_ed25519 \
        -t ed25519 \
        >/dev/null 2>&1
    cp id_ed25519.pub authorized_keys
    cp id_ed25519 "id_ed25519.$(date +"%Y%m%d_%H%M%S")"
    cp id_ed25519.pub "id_ed25519.pub.$(date +"%Y%m%d_%H%M%S")"
    if [ -f "$HOME/mysecret2/.mysecret2.json" ]
    then
        shSecretFileSet id_ed25519 .ssh/id_ed25519
        shSecretFileSet known_hosts .ssh/known_hosts
    fi
)}

shSshReverseTunnelClient() {(set -e
# this function will client-login to ssh-reverse-tunnel
# example use:
# shSshReverseTunnelClient user@localhost:53735 -t bash
    local REMOTE_HOST="$1"
    shift
    local REMOTE_PORT="$(printf $REMOTE_HOST | sed "s/.*://")"
    local REMOTE_HOST="$(printf $REMOTE_HOST | sed "s/:.*//")"
    ssh -p "$REMOTE_PORT" "$REMOTE_HOST" "$@"
)}

shSshReverseTunnelClient2() {(set -e
# this function will client-login to ssh-reverse-tunnel
# example use:
# shSshReverseTunnelClient2 user@proxy:22 user@localhost:53735 -t bash
    local PROXY_HOST="$1"
    shift
    local REMOTE_HOST="$1"
    shift
    local PROXY_PORT="$(printf $PROXY_HOST | sed "s/.*://")"
    local PROXY_HOST="$(printf $PROXY_HOST | sed "s/:.*//")"
    local REMOTE_PORT="$(printf $REMOTE_HOST | sed "s/.*://")"
    local REMOTE_HOST="$(printf $REMOTE_HOST | sed "s/:.*//")"
    ssh -p "$PROXY_PORT" -t "$PROXY_HOST" \
        ssh -p "$REMOTE_PORT" -t "$REMOTE_HOST" "$@"
)}

shSshReverseTunnelServer() {(set -e
# this function will create ssh-reverse-tunnel on server
    shSecretCryptoDecrypt
    shSecretVarExport
    local FILE
    local II
    local PROXY_HOST="$(printf $SSH_REVERSE_PROXY_HOST | sed "s/:.*//")"
    local PROXY_PORT="$(printf $SSH_REVERSE_PROXY_HOST | sed "s/.*://")"
    local REMOTE_PORT="$(printf $SSH_REVERSE_REMOTE_HOST | sed "s/:.*//")"
    if [ "$REMOTE_PORT" = random ]
    then
        REMOTE_PORT="$(shuf -i 32768-65535 -n 1)"
        SSH_REVERSE_REMOTE_HOST=\
"$REMOTE_PORT:$(printf "$SSH_REVERSE_REMOTE_HOST" | sed "s/random://")"
    fi
    # init dir .ssh/
    shSshCryptoDecrypt
    # copy ssh-files to proxy
    scp \
        -P "$PROXY_PORT" \
        "$HOME/.ssh/id_ed25519" "$PROXY_HOST:~/.ssh/" >/dev/null 2>&1
    ssh \
        -p "$PROXY_PORT" \
        "$PROXY_HOST" "chmod 600 ~/.ssh/id_ed25519" >/dev/null 2>&1
    # create ssh-reverse-tunnel from remote to proxy
    ssh \
        -N \
        -R"$SSH_REVERSE_REMOTE_HOST" \
        -T \
        -f \
        -p "$PROXY_PORT" \
        "$PROXY_HOST" >/dev/null 2>&1
    # sleep 10
    # add remote-fingerprint to proxy-known-hosts
    ssh -p "$PROXY_PORT" "$PROXY_HOST" \
        ssh -oStrictHostKeyChecking=no -p "$REMOTE_PORT" \
        "$(whoami)@localhost" : >/dev/null 2>&1
    # loop-print to keep ci awake
    II=-10
    while [ "$II" -lt 60 ] \
        && (ps x | grep "$SSH_REVERSE_REMOTE_HOST" | grep -qv grep)
    do
        II=$((II + 1))
        printf "    $II -- $(date) -- $(whoami)@localhost:$REMOTE_PORT\n"
        if [ "$II" -lt 0 ]
        then
            sleep 5
        else
            sleep 60
        fi
    done
)}