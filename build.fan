// build.fan
using build
class Build : BuildPod
{
  new make()
  {
    podName    = "benies"
    summary    = "Haystack validation for all"
    depends    = ["sys 1.0+", "haystack 3.1", "util 1.0+", "defc 3.1", "def 3.1"]
    srcDirs    = [`fan/`, `test/`]
    resDirs    = [`res/`]
  }
}