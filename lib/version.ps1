########################################
# The code between the fence is just for
# shim to directly use.

# redefine the $GLOBAL_VERSION_FILE
$GLOBAL_VERSION_FILE = "$env:RBENV_ROOT\global.txt"

# We must source it again
. $PSScriptRoot\..\lib\core.ps1
########################################



function get_system_ruby_version_and_path {
    $version, $path = $env:RBENV_SYSTEM_RUBY -split '<=>'
    return $version, $path
}


# Auto fix version number to get close to installed versions
#
# commands using this:
# 1. rbenv-global
# 2. rbenv-local
# 3. rbenv-shell
# 4. rbenv-uninstall
#
function auto_fix_version_for_installed($ver) {
    $versions = get_all_installed_versions

    if ($versions -contains $ver) {
        return $ver
    } else {
        foreach ($i in $versions)  {
            $i = [string] $i
            $ver = [string] $ver
            $idx = $i.IndexOf($ver)
            if ($idx -eq 0) { return $i }
        }
    }
    warn "rbenv: version $ver not installed"
    exit
}


# Auto fix version number to get close to all remote versions
# i.e. versions list
#
# commands using this:
# 1. rbenv-install
#
function auto_fix_version_for_remote($ver) {
    $versions = get_all_remote_versions

    if ($versions -contains $ver) {
        return $ver
    } else {
        foreach ($i in $versions)  {
            $i = [string] $i
            $ver = [string] $ver
            $idx = $i.IndexOf($ver)
            if ($idx -eq 0) { return $i }
        }
    }

    warn "rbenv: version $ver not found"
    exit
}


# Read versions list
function get_all_remote_versions {
    $versions = Get-Content $PSScriptRoot\..\share\versions.txt
    $versions = $versions -split "`n"
    $versions
}


# Read all dir names in the RBENV_ROOT
function get_all_installed_versions {
    # System.IO.DirectoryInfo
    $versions = (Get-ChildItem ($env:RBENV_ROOT)) | Where-Object {
                    $_.Name -match $(version_match_regexp) -or $_.Name -eq 'head'
                }

    # foreach ($ver in $versions) { $ver.Name }

    $versions = $versions | Sort-Object -Descending | ForEach-Object {
        $_.Name
    }

    if ($env:RBENV_SYSTEM_RUBY) {
        if ($versions.Count -eq 0) { $versions = @() }
        if ($versions.Count -eq 1) { $versions = @() + $versions }
        $versions = [Collections.ArrayList] $versions
        $versions.Insert(0, "system")
    }

    $versions
}


# Read the global.txt file
function get_global_version() {
    $version = Get-Content $GLOBAL_VERSION_FILE
    if (!$version) {warn "rbenv: No global version has been set, use rbenv global <version>"}
    else {$version}
}


# Read the .ruby-version file
# Guess why I don't want it to find the Git root directory?
# Because it's too slow: causing another 28ms to delay
# I really don't want it
#
function get_local_version {
    $local_version_file = "$PWD\.ruby-version"
    if (Test-Path $local_version_file) {
        return Get-Content $local_version_file
    } else {
        return $null
    }
}


# Read the global variable
function get_this_shell_version {
    $env:RBENV_VERSION
}


# (current_version  set_by_xxx)
function get_current_version_with_setmsg {
    # Check rbenv shell
    if ($cur_ver = get_this_shell_version) {

        $setmsg = "(set by `$env:RBENV_VERSION environment variable)"
        return $cur_ver, $setmsg

    # Check rbenv local
    } elseif ($cur_ver = get_local_version) {
        if (get_all_installed_versions -contains $cur_ver) {
            $setmsg = "(set by $PWD\.ruby-version)"
            return $cur_ver, $setmsg
        } else {
            warn "rbenv: version $cur_ver is not installed"
        }

    # Check rbenv global
    } elseif ($cur_ver = get_global_version) {
        if (!$cur_ver) {
            warn "rbenv: No version has been set, try 'rbenv global <version>'"
        } else {
            $setmsg = "(set by $env:RBENV_ROOT\global.txt)"
            return $cur_ver, $setmsg
        }
    }
}


# return the bin path for specific version
function get_bin_path_for_version($version) {
    if ($version -eq 'system') {
        $_, $where = get_system_ruby_version_and_path
    } else {
        $where = "$env:RBENV_ROOT\$version"
    }
    $where += "\bin"
    $where
}


# only used in list_who_has
function try_suffix ($where, $name) {

    $suffixes = @( "bat", "cmd" )

    foreach ($s in $suffixes) {
        $any = Get-ChildItem $where "$name.$s"
        if ($any) { return "$where\$name.$s" }
    }
    return $null
}


# rbenv whence
function list_who_has ($name) {

    $versions = get_all_installed_versions

    $whos = @()

    foreach ($ver in $versions) {
        if ($ver -eq 'system') {
            $_, $where = get_system_ruby_version_and_path
            $where = "$where\bin"
        } else {
            $where = "$env:RBENV_ROOT\$ver\bin"
        }
        $who = try_suffix $where $name
        if ($who) { $whos += $who }
        else { continue }
    }

    if ($whos.Count -gt 0) {
        return $whos
    } else {
        return $null
    }
}



# This is called by 'get_executable_location'
#
# Here, $cmd is a Gem's executable name
function get_gem_bin_location_by_version ($cmd, $version) {

    $where = get_bin_path_for_version $version

    # Not use TrimEnd!!
    $cmd = $cmd -replace '.bat$', ''
    $cmd = $cmd -replace '.cmd$', ''

    if (Test-Path ("$where\$cmd" + '.bat')) { return "$where\$cmd.bat" }
    elseif (Test-Path ("$where\$cmd" + '.cmd')) { return "$where\$cmd.cmd" }
    else {
        Write-Host "rbenv: $cmd`: command not found"

        $whos = list_who_has $cmd

        if ($whos) {
            Write-Host "`nThe '$cmd' command exists in these Ruby versions:`n"
            Write-Output $whos
        }
        exit -1
    }
}


# This is called by 'get_executable_location'
#
# Now, only two exe files should be called by this
# 'ruby.exe' and 'rubyw.exe'
function get_ruby_exe_location_by_version ($exe, $version) {
    if (-not $exe.EndsWith('.exe')) {
        $exe = $exe + '.exe'
    }
    $where = get_bin_path_for_version $version

    "$where\$exe"
}


# used by
# 1. command 'rbenv which' (13~18ms)
#    $cmd is a executable name
# 2. shim         (6~8ms)
#    $cmd is a path
function get_executable_location ($cmd) {

    if ($cmd.Contains(':')) {
        # $PSCommandPath must have a : to represent drive
        # So this condition is used by shim
        # E.g.
        # C:Ruby-on-Windows\shims\bin\cr.ps1
        $f = fname $cmd
        # Now cr.ps1
        $cmd = strip_ext $f
    }

    $version, $_ = get_current_version_with_setmsg

    if ($cmd -eq 'ruby' -or $cmd -eq 'rubyw') {
        get_ruby_exe_location_by_version $cmd $version
    } else {
        get_gem_bin_location_by_version  $cmd $version
    }
}
