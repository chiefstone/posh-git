# Initial implementation by Jeremy Skinner
# http://www.jeremyskinner.co.uk/2010/03/07/using-git-with-windows-powershell/

$global:GitTabSettings = New-Object PSObject -Property @{
    AllCommands = $false
}

$global:ops = @{
    remote = 'add','rename','rm','set-head','show','prune','update'
    stash = 'list','show','drop','pop','apply','branch','save','clear','create'
    svn = 'init', 'fetch', 'clone', 'rebase', 'dcommit', 'branch', 'tag', 'log', 'blame', 'find-rev', 'set-tree', 'create-ignore', 'show-ignore', 'mkdirs', 'commit-diff', 'info', 'proplist', 'propget', 'show-externals', 'gc', 'reset'
}

function script:gitCmdOperations($command, $filter) {
    $ops.$command |
        where { $_ -like "$filter*" }
}

function script:gitCommands($filter, $includeAliases) {
    $cmdList = @()
    if (-not $global:GitTabSettings.AllCommands) {
        $cmdList += git help |
            foreach { if($_ -match '^   (\S+) (.*)') { $matches[1] } } |
            where { $_ -like "$filter*" }
    } else {
        $cmdList += git help --all |
            where { $_ -match '^  \S.*' } |
            foreach { $_.Split(' ', [StringSplitOptions]::RemoveEmptyEntries) } |
            where { $_ -like "$filter*" }
    }

    if ($includeAliases) {
        $cmdList += gitAliases $filter
    }
    $cmdList | sort
}

function script:gitRemotes($filter) {
    git remote |
        where { $_ -like "$filter*" }
}

function script:gitLocalBranches($filter, $includeHEAD = $false) {
    $branches = git branch |
        foreach { if($_ -match "^\*?\s*(.*)") { $matches[1] } }

    @(if ($includeHEAD) { 'HEAD' }) + @($branches) |
        where { $_ -ne '(no branch)' -and $_ -like "$filter*" }
}

function script:gitStashes($filter) {
    (git stash list) -replace ':.*','' |
        where { $_ -like "$filter*" } |
        foreach { "'$_'" }
}

function script:gitIndex($filter) {
    if($GitStatus) {
        $GitStatus.Index |
            where { $_ -like "$filter*" } |
            foreach { if($_ -like '* *') { "'$_'" } else { $_ } }
    }
}

function script:gitFiles($filter) {
    if($GitStatus) {
        $GitStatus.Working |
            where { $_ -like "$filter*" } |
            foreach { if($_ -like '* *') { "'$_'" } else { $_ } }
    }
}

function script:gitDeleted($filter) {
    if($GitStatus) {
        $GitStatus.Working.Deleted |
            where { $_ -like "$filter*" } |
            foreach { if($_ -like '* *') { "'$_'" } else { $_ } }
    }
}

function script:gitAliases($filter) {
    git config --get-regexp ^alias\. | foreach {
        if($_ -match "^alias\.(?<alias>\S+) .*") {
            $alias = $Matches['alias']
            if($alias -like "$filter*") {
                $alias
            }
        }
    } | Sort
}

function script:expandGitAlias($cmd, $rest) {
    if((git config --get-regexp "^alias\.$cmd`$") -match "^alias\.$cmd (?<cmd>[^!]\S+) .*`$") {
        return "git $($Matches['cmd'])$rest"
    } else {
        return "git $cmd$rest"
    }
}

function GitTabExpansion($lastBlock) {
    if($lastBlock -match '^git (?<cmd>\S+)(?<args> .*)$') {
        $lastBlock = expandGitAlias $Matches['cmd'] $Matches['args']
    }

    switch -regex ($lastBlock) {

        # Handles tgit <command> (tortoisegit)
        '^tgit (\S*)$' {
            # Need return statement to prevent fall-through.
            return $tortoiseGitCommands | where { $_ -like "$($matches[1])*" }
        }

        # Handles git remote <op>
        # Handles git stash <op>
        '^git (?<cmd>remote|stash|svn) (?<op>\S*)$' {
            gitCmdOperations $matches['cmd'] $matches['op']
        }

        # Handles git remote (rename|rm|set-head|set-branches|set-url|show|prune) <stash>
        '^git remote.* (?:rename|rm|set-head|set-branches|set-url|show|prune).* (?<remote>\S*)$' {
            gitRemotes $matches['remote']
        }

        # Handles git stash (show|apply|drop|pop|branch) <stash>
        '^git stash (?:show|apply|drop|pop|branch).* (?<stash>\S*)$' {
            gitStashes $matches['stash']
        }

        # Handles git branch -d|-D|-m|-M <branch name>
        # Handles git branch <branch name> <start-point>
        '^git branch.* (?<branch>\S*)$' {
            gitLocalBranches $matches['branch']
        }

        # Handles git <cmd> (commands & aliases)
        '^git (?<cmd>\S*)$' {
            gitCommands $matches['cmd'] $TRUE
        }

        # Handles git help <cmd> (commands only)
        '^git help (?<cmd>\S*)$' {
            gitCommands $matches['cmd'] $FALSE
        }

        # Handles git push remote <branch>
        # Handles git pull remote <branch>
        '^git (?:push|pull).* (?:\S+) (?<branch>\S*)$' {
            gitLocalBranches $matches['branch']
        }

        # Handles git pull <remote>
        # Handles git push <remote>
        # Handles git fetch <remote>
        '^git (?:push|pull|fetch).* (?<remote>\S*)$' {
            gitRemotes $matches['remote']
        }

        # Handles git reset HEAD <path>
        # Handles git reset HEAD -- <path>
        '^git reset.* HEAD(?:\s+--)? (?<path>\S*)$' {
            gitIndex $matches['path']
        }

        # Handles git cherry-pick <commit>
        # Handles git diff <commit>
        # Handles git difftool <commit>
        # Handles git log <commit>
        # Handles git show <commit>
        '^git (?:cherry-pick|diff|difftool|log|show).* (?<commit>\S*)$' {
            gitLocalBranches $matches['commit']
        }

        # Handles git reset <commit>
        '^git reset.* (?<commit>\S*)$' {
            gitLocalBranches $matches['commit'] $true
        }

        # Handles git add <path>
        '^git add.* (?<files>\S*)$' {
            gitFiles $matches['files']
        }

        # Handles git checkout -- <path>
        '^git checkout.* -- (?<files>\S*)$' {
            gitFiles $matches['files']
        }

        # Handles git rm <path>
        '^git rm.* (?<index>\S*)$' {
            gitDeleted $matches['index']
        }

        # Handles git checkout <branch name>
        # Handles git merge <branch name>
        # handles git rebase <branch name>
        '^git (?:checkout|merge|rebase).* (?<branch>\S*)$' {
            gitLocalBranches $matches['branch']
        }
    }
}
