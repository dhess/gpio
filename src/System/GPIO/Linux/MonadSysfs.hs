-- | Monads in which low-level Linux 'sysfs' GPIO operations can be
-- embedded.
--
-- If you want to write low-level, Linux-specific GPIO programs
-- without the overhead (and cross-platform portability!) of the
-- 'Control.Monad.Trans.Free.FreeT' transformer, you can use this
-- typeclass directly.

module System.GPIO.Linux.MonadSysfs
       ( -- * MonadSysfs class
         MonadSysfs(..)
        -- * Convenience functions
       , sysfsPath
       , exportFileName
       , unexportFileName
       , pinDirName
       , pinActiveLowFileName
       , pinDirectionFileName
       , pinEdgeFileName
       , pinValueFileName
       ) where

import Control.Monad.IO.Class (MonadIO)
import Control.Monad.Trans.Class (lift)
import Control.Monad.Trans.Cont (ContT)
import Control.Monad.Trans.Except (ExceptT)
import Control.Monad.Trans.List (ListT)
import Control.Monad.Trans.Maybe (MaybeT)
import Control.Monad.Trans.Reader (ReaderT)
import qualified Control.Monad.Trans.RWS.Lazy as LazyRWS (RWST)
import qualified Control.Monad.Trans.RWS.Strict as StrictRWS (RWST)
import qualified Control.Monad.Trans.State.Lazy as LazyState (StateT)
import qualified Control.Monad.Trans.State.Strict as StrictState (StateT)
import qualified Control.Monad.Trans.Writer.Lazy as LazyWriter (WriterT)
import qualified Control.Monad.Trans.Writer.Strict as StrictWriter (WriterT)
import System.FilePath ((</>))
import System.GPIO.Types

-- | The base path to Linux's 'sysfs' GPIO filesystem.
sysfsPath :: FilePath
sysfsPath = "/sys/class/gpio"

-- | The name of the control file used to export GPIO pins via
-- 'sysfs'.
exportFileName :: FilePath
exportFileName = sysfsPath </> "export"

-- | The name of the control file used to "unexport" GPIO pins via
-- 'sysfs'.
unexportFileName :: FilePath
unexportFileName = sysfsPath </> "unexport"

-- | Exporting a GPIO pin via 'sysfs' creates a control directory
-- corresponding to that pin. 'pinDirName' gives the name of that
-- directory for a given pin number.
pinDirName :: Pin -> FilePath
pinDirName (Pin n) = sysfsPath </> ("gpio" ++ show n)

-- | The name of the attribute file used to read and write the pin's
-- "active low" value.
pinActiveLowFileName :: Pin -> FilePath
pinActiveLowFileName p = pinDirName p </> "active_low"

-- | Pins whose direction can be controlled via 'sysfs' provide a
-- "direction" attribute file. 'pinDirectionFileName' gives the name
-- of that file for a given pin number. Note that some pins' direction
-- cannot be set. In these cases, the file named by this function does
-- not actually exist.
pinDirectionFileName :: Pin -> FilePath
pinDirectionFileName p = pinDirName p </> "direction"

-- | Pins that can be configured as interrupt-generating inputs
-- provide an "edge" attribute file. 'pinEdgeFileName' gives the name
-- of that file for a given pin number. Note that some pins' edge
-- configuration cannot be set. In these cases, the file named by this
-- function does not actually exist.
pinEdgeFileName :: Pin -> FilePath
pinEdgeFileName p = pinDirName p </> "edge"

-- | The name of the attribute file used to read and write the pin's
-- logical signal value.
pinValueFileName :: Pin -> FilePath
pinValueFileName p = pinDirName p </> "value"


-- | Monads in which low-level Linux 'sysfs' GPIO-like operations may be
-- embedded.
class (Monad m) => MonadSysfs m where

  -- | Test whether the 'sysfs' GPIO filesystem is available.
  sysfsIsPresent :: m Bool

  -- | Test whether the given pin is already exported.
  pinIsExported :: Pin -> m Bool

  -- | Test whether the given pin's direction can be set via the
  -- 'sysfs' GPIO filesystem. (Some pins have a hard-wired direction,
  -- in which case their direction must be determined by some other
  -- mechanism as the "direction" attribute does not exist for such
  -- pins.)
  pinHasDirection :: Pin -> m Bool

  -- | Export the given pin.
  exportPin :: Pin -> m ()

  -- | Unexport the given pin.
  --
  -- It is an error to call this function if the pin is not currently
  -- exported.
  unexportPin :: Pin -> m ()

  -- | Read the given pin's direction.
  --
  -- It is an error to call this function if the pin has no
  -- "direction" attribute in the 'sysfs' GPIO filesystem.
  readPinDirection :: Pin -> m PinDirection

  -- | Set the given pin's direction.
  --
  -- It is an error to call this function if the pin has no
  -- "direction" attribute in the 'sysfs' GPIO filesystem.
  writePinDirection :: Pin -> PinDirection -> m ()

  -- | Pins whose direction can be set may be configured for output by
  -- writing a 'PinValue' to their 'sysfs' "direction" attribute. This
  -- enables glitch-free output configuration, assuming the pin is
  -- currently configured for input, or some kind of tri-stated or
  -- floating high-impedance mode.
  --
  -- It is an error to call this function if the pin has no
  -- "direction" attribute in the 'sysfs' GPIO filesystem.
  writePinDirectionWithValue :: Pin -> PinValue -> m ()

  -- | Read the given pin's value.
  --
  -- Note that this function never blocks, regardless of the pin's
  -- "edge" attribute setting.
  readPinValue :: Pin -> m PinValue

  -- | A blocking version of 'readPinValue'. The current thread will
  -- block until an event occurs on the pin as specified by the pin's
  -- current "edge" attribute setting. (If the pin has no "edge"
  -- attribute, then this function will not block and will act like
  -- 'readPinValue'.)
  --
  -- This function is implemented via the C language FFI and is
  -- annotated as @interruptible@. If your program is compiled with
  -- GHC using the @-threaded@ option, this function will not block
  -- other Haskell threads.
  threadWaitReadPinValue :: Pin -> m PinValue

  -- | Set the given pin's value.
  --
  -- It is an error to call this function if the pin is configured as
  -- an input pin.
  writePinValue :: Pin -> PinValue -> m ()

  -- | Test whether the pin has an "edge" 'sysfs' attribute, i.e.,
  -- whether it can be configured for edge- or level-triggered
  -- interrupts.
  pinHasEdge :: Pin -> m Bool

  -- | Read the given pin's "edge" 'sysfs' attribute.
  --
  -- It is an error to call this function when the pin has no "edge"
  -- attribute.
  readPinEdge :: Pin -> m PinReadTrigger

  -- | Write the given pin's "edge" 'sysfs' attribute.
  --
  -- It is an error to call this function when the pin has no "edge"
  -- attribute.
  writePinEdge :: Pin -> PinReadTrigger -> m ()

  -- | Read the given pin's "active_low" 'sysfs' attribute.
  readPinActiveLow :: Pin -> m Bool

  -- | Write the given pin's "active_low" 'sysfs' attribute.
  writePinActiveLow :: Pin -> Bool -> m ()

  -- | Return a list of all pins that are exposed via the 'sysfs' GPIO
  -- filesystem. Note that the returned list may omit some pins that
  -- are available on the host but which, for various reasons, are not
  -- exposed via the 'sysfs' GPIO filesystem.
  availablePins :: m [Pin]

instance (MonadIO m, MonadSysfs m) => MonadSysfs (ContT r m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (ExceptT e m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (ListT m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (MaybeT m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (ReaderT r m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m, Monoid w) => MonadSysfs (LazyRWS.RWST r w s m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m, Monoid w) => MonadSysfs (StrictRWS.RWST r w s m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (LazyState.StateT s m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m) => MonadSysfs (StrictState.StateT s m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m, Monoid w) => MonadSysfs (LazyWriter.WriterT w m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins

instance (MonadIO m, MonadSysfs m, Monoid w) => MonadSysfs (StrictWriter.WriterT w m) where
  sysfsIsPresent = lift sysfsIsPresent
  pinIsExported = lift . pinIsExported
  pinHasDirection = lift . pinHasDirection
  pinHasEdge = lift . pinHasEdge
  exportPin = lift . exportPin
  unexportPin = lift . unexportPin
  readPinDirection = lift . readPinDirection
  writePinDirection h d = lift $ writePinDirection h d
  writePinDirectionWithValue h v = lift $ writePinDirectionWithValue h v
  readPinValue = lift . readPinValue
  threadWaitReadPinValue = lift . threadWaitReadPinValue
  writePinValue h v = lift $ writePinValue h v
  readPinEdge = lift . readPinEdge
  writePinEdge h x = lift $ writePinEdge h x
  readPinActiveLow = lift . readPinActiveLow
  writePinActiveLow h v = lift $ writePinActiveLow h v
  availablePins = lift availablePins
