local lib = require("src.lib")

describe("lib", function()
    describe("trim", function()
        it("strips leading and trailing whitespace", function()
            assert.are.equal("hello", lib.trim("  hello  "))
        end)

        it("strips newlines", function()
            assert.are.equal("abc", lib.trim("abc\n"))
            assert.are.equal("abc", lib.trim("\nabc\n"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(lib.trim(nil))
        end)

        it("returns empty string for empty input", function()
            assert.are.equal("", lib.trim(""))
        end)

        it("preserves internal spaces", function()
            assert.are.equal("hello world", lib.trim("  hello world  "))
        end)
    end)

    describe("is_valid_sha256", function()
        it("accepts a valid 64-char hex string", function()
            assert.is_true(lib.is_valid_sha256("abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"))
        end)

        it("rejects a short hex string", function()
            assert.is_false(lib.is_valid_sha256("abcdef"))
        end)

        it("rejects non-hex characters", function()
            assert.is_false(lib.is_valid_sha256("zzzzzz0123456789abcdef0123456789abcdef0123456789abcdef0123456789"))
        end)

        it("returns false for nil", function()
            assert.is_false(lib.is_valid_sha256(nil))
        end)

        it("accepts a hash with surrounding whitespace", function()
            assert.is_true(lib.is_valid_sha256("  abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789\n"))
        end)
    end)

    describe("parse_sha256_from_output", function()
        local hash = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

        it("parses a plain hash", function()
            assert.are.equal(hash, lib.parse_sha256_from_output(hash))
        end)

        it("parses a hash with trailing newline", function()
            assert.are.equal(hash, lib.parse_sha256_from_output(hash .. "\n"))
        end)

        it("parses CertUtil multi-line output", function()
            local certutil = "SHA256 hash of file:\n" .. hash .. "\nCertUtil: -hashfile command completed successfully."
            assert.are.equal(hash, lib.parse_sha256_from_output(certutil))
        end)

        it("parses sha256sum format (hash followed by filename)", function()
            local output = hash .. "  postgresql-15.10.0.tar.gz\n"
            assert.are.equal(hash, lib.parse_sha256_from_output(output))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(lib.parse_sha256_from_output(nil))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(lib.parse_sha256_from_output(""))
        end)

        it("returns nil when no 64-char hex found", function()
            assert.is_nil(lib.parse_sha256_from_output("no hash here"))
        end)

        it("lowercases uppercase hash", function()
            local upper = "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789"
            assert.are.equal(hash, lib.parse_sha256_from_output(upper))
        end)
    end)

    describe("parse_major_version", function()
        it("parses semver string", function()
            assert.are.equal(15, lib.parse_major_version("15.10.0"))
        end)

        it("parses two-part version", function()
            assert.are.equal(14, lib.parse_major_version("14.2"))
        end)

        it("returns nil for non-numeric input", function()
            assert.is_nil(lib.parse_major_version("latest"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(lib.parse_major_version(nil))
        end)

        it("returns nil for empty string", function()
            assert.is_nil(lib.parse_major_version(""))
        end)
    end)

    describe("get_rust_target", function()
        it("returns darwin amd64 target", function()
            assert.are.equal("x86_64-apple-darwin", lib.get_rust_target("darwin", "amd64"))
        end)

        it("returns darwin arm64 target", function()
            assert.are.equal("aarch64-apple-darwin", lib.get_rust_target("darwin", "arm64"))
        end)

        it("returns linux amd64 gnu target", function()
            assert.are.equal("x86_64-unknown-linux-gnu", lib.get_rust_target("linux", "amd64", false))
        end)

        it("returns linux amd64 musl target", function()
            assert.are.equal("x86_64-unknown-linux-musl", lib.get_rust_target("linux", "amd64", true))
        end)

        it("returns linux arm64 gnu target", function()
            assert.are.equal("aarch64-unknown-linux-gnu", lib.get_rust_target("linux", "arm64", false))
        end)

        it("returns linux arm64 musl target", function()
            assert.are.equal("aarch64-unknown-linux-musl", lib.get_rust_target("linux", "arm64", true))
        end)

        it("returns linux 386 gnu target", function()
            assert.are.equal("i686-unknown-linux-gnu", lib.get_rust_target("linux", "386", false))
        end)

        it("returns linux 386 musl target", function()
            assert.are.equal("i686-unknown-linux-musl", lib.get_rust_target("linux", "386", true))
        end)

        it("returns windows amd64 target", function()
            assert.are.equal("x86_64-pc-windows-msvc", lib.get_rust_target("windows", "amd64"))
        end)

        it("returns nil for unsupported OS", function()
            assert.is_nil(lib.get_rust_target("freebsd", "amd64"))
        end)

        it("returns nil for unsupported arch", function()
            assert.is_nil(lib.get_rust_target("darwin", "mips"))
        end)
    end)

    describe("normalize_path", function()
        it("converts forward slashes to backslashes on windows", function()
            assert.are.equal("C:\\Users\\test\\file", lib.normalize_path("C:/Users/test/file", "windows"))
        end)

        it("passes through on linux", function()
            assert.are.equal("/home/test/file", lib.normalize_path("/home/test/file", "linux"))
        end)

        it("handles mixed separators on windows", function()
            assert.are.equal("C:\\path\\to\\file", lib.normalize_path("C:\\path/to/file", "windows"))
        end)

        it("returns nil for nil input", function()
            assert.is_nil(lib.normalize_path(nil, "linux"))
        end)
    end)
end)
