module Fibon.Run.BenchmarkBundle (
    BenchmarkBundle(..)
  , mkBundle
  , bundleName
  , pathToBench
  , pathToCabalWorkDir
  , pathToExeBuildDir
  , pathToExe
  , pathToSizeInputFiles
  , pathToSizeOutputFiles
  , pathToAllInputFiles
  , pathToAllOutputFiles
  , pathToSizeDataFiles
  , pathToStdoutFile
  , pathToStderrFile
  , pathToExeRunDir
  , pathToStdinFile
  , prettyRunCommand
  , bundleProcessSpec
  , benchExeAndArgs
)
where

import Data.Char
import Data.List
import Fibon.Benchmarks
import Fibon.BenchmarkInstance
import Fibon.Timeout
import Fibon.Run.Config
import System.FilePath
import System.IO
import System.Process
import System.Info


data BenchmarkBundle = BenchmarkBundle {
      benchmark     :: FibonBenchmark
    , workDir       :: FilePath
    , benchDir      :: FilePath
    , unique        :: String
    , iters         :: Int
    , tuneSetting   :: TuneSetting
    , inputSize     :: InputSize
    , fullFlags     :: FlagConfig
    , benchDetails  :: BenchmarkInstance
    , timeout       :: Maybe Int
    , extraStats    :: Maybe FilePath
    , runScript     :: Maybe (FilePath, [String])
  } deriving (Show)

mkBundle :: RunConfig
         -> FibonBenchmark
         -> FilePath -- ^ working directory
         -> FilePath -- ^ benchmarks directory
         -> String   -- ^ unique id
         -> InputSize
         -> TuneSetting
         -> [(String, String)] -- ^ Environment variables
         -> BenchmarkBundle
mkBundle rc bm wd bmsDir uniq size tune progEnv =
  BenchmarkBundle {
      benchmark     = bm
    , workDir       = wd
    , benchDir      = bmsDir
    , unique        = uniq
    , iters         = (iterations rc)
    , tuneSetting   = tune
    , inputSize     = size
    , fullFlags     = flags configuration
    , benchDetails  = benchInstance bm size
    , timeout       = timeoutToMicroSeconds (limit configuration)
    , extraStats    = (extraStatsFile configuration)
    , runScript     = (wrapperScript configuration)
  }
  where
    configuration = mkConfig rc bm size tune progEnv

bundleName :: BenchmarkBundle -> String
bundleName bb = concat $ intersperse "-"
  [(show $ benchmark bb), (show $ inputSize bb), (show $ tuneSetting bb)]

pathToBench :: BenchmarkBundle -> FilePath
pathToBench bb = (benchDir bb) </> ((benchPath . benchmark) bb)

pathToCabalWorkDir :: BenchmarkBundle -> FilePath
pathToCabalWorkDir bb = (workDir bb) </> (unique bb) </> (bundleName bb)

pathToExeBuildDir :: BenchmarkBundle -> FilePath
pathToExeBuildDir bb = 
  (pathToCabalWorkDir bb) </> "build" </> (exeName.benchDetails $ bb)

pathToExeRunDir :: BenchmarkBundle -> FilePath
pathToExeRunDir = pathToExeBuildDir

pathToExe :: BenchmarkBundle -> FilePath
pathToExe bb = (pathToExeBuildDir bb) </> (exeName.benchDetails $ bb)++ext
  where ext = if System.Info.os == "mingw32" then ".exe" else ""

pathToSizeInputFiles :: BenchmarkBundle -> FilePath
pathToSizeInputFiles = pathToSizeDataFiles "input"

pathToSizeOutputFiles :: BenchmarkBundle -> FilePath
pathToSizeOutputFiles = pathToSizeDataFiles "output"

pathToAllInputFiles :: BenchmarkBundle -> FilePath
pathToAllInputFiles = pathToAllDataFiles "input"

pathToAllOutputFiles :: BenchmarkBundle -> FilePath
pathToAllOutputFiles = pathToAllDataFiles "output"

pathToSizeDataFiles :: FilePath -> BenchmarkBundle -> FilePath
pathToSizeDataFiles subDir bb = pathToDataFiles size subDir bb
  where
  size = (map toLower $ show $ inputSize bb)

pathToAllDataFiles :: FilePath -> BenchmarkBundle -> FilePath
pathToAllDataFiles = pathToDataFiles "all"

pathToDataFiles :: FilePath -> FilePath -> BenchmarkBundle -> FilePath
pathToDataFiles size subDir bb =
  (pathToBench bb) </> "Fibon" </> "data" </> size </> subDir

pathToStdoutFile :: BenchmarkBundle -> FilePath
pathToStdoutFile = pathToStdioFile "stdout"

pathToStderrFile :: BenchmarkBundle -> FilePath
pathToStderrFile = pathToStdioFile "stderr"

pathToStdioFile :: String -> BenchmarkBundle -> FilePath
pathToStdioFile name bb =
  (pathToExeRunDir bb) </> (exeName.benchDetails $ bb) ++"."++name++".actual"

pathToStdinFile :: BenchmarkBundle -> FilePath -> FilePath
pathToStdinFile bb inFile = (pathToExeRunDir bb) </> inFile

benchExeAndArgs :: BenchmarkBundle -> (String, [String])
benchExeAndArgs bb =
  case runScript bb of
    Nothing -> (realExe, realFlags)
    Just (wrapper, args) -> (wrapper, args ++ realExe : realFlags)
  where
  realExe   = pathToExe bb
  realFlags = (runFlags . fullFlags) bb

prettyRunCommand :: BenchmarkBundle -> String
prettyRunCommand bb = cmd
  where
  cmd        = exe  ++ (concatMap (' ':) fullArgs)
  fullArgs   = args ++ stdioArgs
  (exe,args) = benchExeAndArgs bb
  stdioArgs  = [stdIn, stdOut, stdErr]
  stdIn      = case (stdinInput.benchDetails $ bb) of
                    Nothing -> ""
                    Just f  -> " < " ++ pathToStdinFile bb f
  stdOut     = "  > " ++ (pathToStdoutFile bb)
  stdErr     = " 2> " ++ (pathToStderrFile bb)

bundleProcessSpec :: BenchmarkBundle -> IO CreateProcess
bundleProcessSpec bb = do
  stdIn <-
    case  (stdinInput.benchDetails $ bb) of
      Nothing -> do return CreatePipe
      Just f  -> do h <- openFile (pathToStdinFile bb f) ReadMode
                    return (UseHandle h)
  out <- openFile (pathToStdoutFile bb) WriteMode
  err <- openFile (pathToStderrFile bb) WriteMode
  return $ (proc exe args) {
        cwd     = Just (pathToExeRunDir bb)
      , std_in  = stdIn
      , std_out = UseHandle out
      , std_err = UseHandle err
  }
  where
  (exe, args) = benchExeAndArgs bb

