Deploy 'Deploy Module' {
    By Filesystem Modules {
        FromSource "$((Get-Item $PSScriptRoot).Parent.FullName)\src"
        To "$env:Temp\OmadaWeb.PS"
        Tagged Prod
    }
}