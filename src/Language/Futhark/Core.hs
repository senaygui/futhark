-- | This module contains very basic definitions for Futhark - so basic,
-- that they can be shared between the internal and external
-- representation.
module Language.Futhark.Core
  ( Uniqueness(..)
  , StreamOrd(..)
  , Commutativity(..)

  -- * Location utilities
  , locStr

  -- * Name handling
  , Name
  , nameToString
  , nameFromString
  , nameToText
  , nameFromText
  , ID(..)
  , baseTag
  , baseName
  , baseString
  , VName
  , textual

  -- * Special identifiers
  , defaultEntryPoint

    -- * Integer re-export
  , Int8, Int16, Int32, Int64
  )

where

import Data.Monoid
import Data.Hashable
import Data.Int (Int8, Int16, Int32, Int64)
import Data.Loc
import qualified Data.Text as T

import Prelude

import Futhark.Util.Pretty

-- | The uniqueness attribute of a type.  This essentially indicates
-- whether or not in-place modifications are acceptable.  With respect
-- to ordering, 'Unique' is greater than 'Nonunique'.
data Uniqueness = Nonunique -- ^ May have references outside current function.
                | Unique    -- ^ No references outside current function.
                  deriving (Eq, Ord, Show)

instance Monoid Uniqueness where
  mempty = Unique
  _ `mappend` Nonunique = Nonunique
  Nonunique `mappend` _ = Nonunique
  u `mappend` _         = u

instance Hashable Uniqueness where
  hashWithSalt salt Unique    = salt
  hashWithSalt salt Nonunique = salt * 2

data StreamOrd  = InOrder
                | Disorder
                    deriving (Eq, Ord, Show)

-- | Whether some operator is commutative or not.  The 'Monoid'
-- instance returns the least commutative of its arguments.
data Commutativity = Noncommutative
                   | Commutative
                     deriving (Eq, Ord, Show)

instance Monoid Commutativity where
  mempty = Commutative
  mappend = min

-- | The name of the default program entry point (main).
defaultEntryPoint :: Name
defaultEntryPoint = nameFromString "main"

-- | The abstract (not really) type representing names in the Futhark
-- compiler.  'String's, being lists of characters, are very slow,
-- while 'T.Text's are based on byte-arrays.
newtype Name = Name T.Text
  deriving (Show, Eq, Ord)

instance Pretty Name where
  ppr = text . nameToString

instance Hashable Name where
  hashWithSalt salt (Name t) = hashWithSalt salt t

instance Monoid Name where
  Name t1 `mappend` Name t2 = Name $ t1 <> t2
  mempty = Name mempty

-- | Convert a name to the corresponding list of characters.
nameToString :: Name -> String
nameToString (Name t) = T.unpack t

-- | Convert a list of characters to the corresponding name.
nameFromString :: String -> Name
nameFromString = Name . T.pack

-- | Convert a name to the corresponding 'T.Text'.
nameToText :: Name -> T.Text
nameToText (Name t) = t

-- | Convert a 'T.Text' to the corresponding name.
nameFromText :: T.Text -> Name
nameFromText = Name

-- | A human-readable location string, of the form
-- @filename:lineno:columnno@.
locStr :: SrcLoc -> String
locStr (SrcLoc NoLoc) = "unknown location"
locStr (SrcLoc (Loc (Pos file line1 col1 _) (Pos _ line2 col2 _))) =
  -- Assume that both positions are in the same file (what would the
  -- alternative mean?)
  file ++ ":" ++ show line1 ++ ":" ++ show col1
       ++ "-" ++ show line2 ++ ":" ++ show col2

-- | An arbitrary value tagged with some integer.  Only the integer is
-- used in comparisons, no matter the type of @vn@.
newtype ID vn = ID (vn, Int)
  deriving (Show)

-- | Alias for a tagged 'Name'.  This is used as the name
-- representation in most the compiler.
type VName = ID Name

-- | Return the tag contained in the 'ID'.
baseTag :: ID vn -> Int
baseTag (ID (_, tag)) = tag

-- | Return the name contained in the 'ID'.
baseName :: ID vn -> vn
baseName (ID (vn, _)) = vn

-- | Return the base 'Name' converted to a string.
baseString :: VName -> String
baseString = nameToString . baseName

instance Eq (ID vn) where
  ID (_, x) == ID (_, y) = x == y

instance Ord (ID vn) where
  ID (_, x) `compare` ID (_, y) = x `compare` y

instance Pretty vn => Pretty (ID vn) where
  ppr (ID (vn, i)) = ppr vn <> text "_" <> text (show i)

instance Hashable (ID vn) where
  hashWithSalt salt (ID (_,i)) = salt * i

textual :: VName -> String
textual = pretty
