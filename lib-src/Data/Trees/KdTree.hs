{-# LANGUAGE DeriveGeneric #-}

module Data.Trees.KdTree
       ( -- * Introduction

         -- $intro

         -- * Usage

         -- $usage

         -- * Variants

         -- ** Dynamic /k/-d trees

         -- $dkdtrees

         -- ** /k/-d maps

         -- $kdmaps

         -- * Advanced

         -- ** Custom distance functions

         -- $customdistancefunctions

         -- ** Axis value types

         -- $axisvaluetypes

         -- * Reference

         PointAsListFn
       , KdTree
       , buildKdTree
       , SquaredDistanceFn
       , defaultDistSqrFn
       , buildKdTreeWithDistFn
       , nearestNeighbor
       , nearNeighbors
       , kNearestNeighbors
       , points
       , size
       ) where

import Control.DeepSeq
import Control.DeepSeq.Generics (genericRnf)
import GHC.Generics

import Data.Foldable

import qualified Data.Trees.KdMap as KDM
import Data.Trees.KdMap (PointAsListFn, SquaredDistanceFn, defaultDistSqrFn)

-- $intro
--
-- Let's say you have a large set of 3D points called /data points/,
-- and you'd like to be able to quickly perform /point queries/ on the
-- data points. One example of a point query is the /nearest neighbor/
-- query: given a set of data points @points@ and a query point @p@,
-- which point in @points@ is closest to @p@?
--
-- We can efficiently solve the nearest neighbor query (along with
-- many other types of point queries) if we appropriately organize the
-- data points. One such method of organization is called the /k/-d
-- tree algorithm, which is implemented in this module.

-- $usage
--
-- Let's say you have a list of 3D data points, and each point is of
-- type @Point3d@:
--
-- @
-- data Point3d = Point3d { _x :: Double
--                        , _y :: Double
--                        , _z :: Double
--                        } deriving Show
-- @
--
-- We call a point's individual values /axis values/ (i.e., @x@, @y@,
-- and @z@ in the case of @Point3d@).
--
-- In order to generate a /k/-d tree of @Point3d@'s, we need to define
-- a 'PointAsListFn' that expresses the point's axis values as a list:
--
-- @
-- point3dAsList :: Point3d -> [Double]
-- point3dAsList (Point3d x y z) = [x, y, z]
-- @
--
-- Now we can build a 'KdTree' structure from a list of data points
-- and perform a nearest neighbor query as follows:
--
-- @
-- >>> let dataPoints = [(Point3d 0.0 0.0 0.0), (Point3d 1.0 1.0 1.0)]
--
-- >>> let kdt = 'buildKdTree' point3dAsList dataPoints
--
-- >>> let queryPoint = Point3d 0.1 0.1 0.1
--
-- >>> 'nearestNeighbor' kdt queryPoint
-- Point3d 0.0 0.0 0.0
-- @

-- $dkdtrees
--
-- The 'KdTree' structure is meant for static sets of data points. If
-- you need to insert points into an existing /k/-d tree, check out
-- the 'Data.Trees.DynKdTree' module.

-- $kdmaps
--
-- If you need to associate additional data with each point in the
-- tree (i.e., points are /keys/ associated with /values/), check out
-- the 'Data.Trees.KdMap' and 'Data.Trees.DynKdMap' modules for
-- static and dynamic variants of this functionality. Please /do not/
-- try to fake this functionality with a 'KdTree' by augmenting your
-- point type with the extra data; you're gonna have a bad time.

-- $customdistancefunctions
--
-- You may have noticed in the previous use case that we never
-- specified what "nearest" means for our points. By default,
-- 'buildKdTree' uses a Euclidean distance function that is sufficient
-- in most cases. However, point queries are typically faster on a
-- 'KdTree' built with a user-specified custom distance
-- function. Let's generate a 'KdTree' using a custom distance
-- function.
--
-- One idiosyncrasy about 'KdTree' is that custom distance functions
-- are actually specified as /squared distance/ functions
-- ('SquaredDistanceFn'). This means that your custom distance
-- function must return the /square/ of the actual distance between
-- two points. This is for efficiency: regular distance functions
-- often require expensive square root computations, whereas in our
-- case, the squared distance works fine and doesn't require computing
-- any square roots. Here's an example of a squared distance function
-- for @Point3d@:
--
-- @
-- point3dSquaredDistance :: Point3d -> Point3d -> Double
-- point3dSquaredDistance (Point3d x1 y1 z1) (Point3d x2 y2 z2) =
--   let dx = x1 - x2
--       dy = y1 - y2
--       dz = z1 - z2
--   in  dx * dx + dy * dy + dz * dz
-- @
--
-- We can build a 'KdTree' using our custom distance function as follows:
--
-- @
-- >>> let kdt = 'buildKdTreeWithDistFn' point3dAsList point3dSquaredDistance points
-- @

-- $axisvaluetypes
--
-- In the above examples, we used a point type with axis values of
-- type 'Double'. We can in fact use axis values of any type that is
-- an instance of the 'Real' typeclass. This means you can use points
-- that are composed of 'Double's, 'Int's, 'Float's, and so on:
--
-- @
-- data Point2i = Point2i Int Int
--
-- point2iAsList :: Point2i -> [Int]
-- point2iAsList (Point2i x y) = [x, y]
--
-- kdt :: [Point2i] -> KdTree Int Point2i
-- kdt dataPoints = buildKdTree point2iAsList dataPoints
-- @

-- | A /k/-d tree structure that stores points of type @p@ with axis
-- values of type @a@.
newtype KdTree a p = KdTree (KDM.KdMap a p ()) deriving Generic
instance (NFData a, NFData p) => NFData (KdTree a p) where rnf = genericRnf

instance Foldable (KdTree a) where
  foldr f z (KdTree kdMap) = KDM.foldrKdMap (f . fst) z kdMap

-- | Builds a 'KdTree' from a list of data points using a default
-- squared distance function 'defaultDistSqrFn'.
--
-- Average complexity: /O(n * log(n))/ for /n/ data points.
--
-- Worse case space complexity: /O(n)/ for /n/ data points.
--
-- Throws an error if given an empty list of data points.
buildKdTree :: Real a => PointAsListFn a p
                         -> [p] -- ^ non-empty list of data points to be stored in the /k/-d tree
                         -> KdTree a p
buildKdTree _ [] = error "KdTree must be built with a non-empty list."
buildKdTree pointAsList ps =
  KdTree $ KDM.buildKdMap pointAsList $ zip ps $ repeat ()

-- | Builds a 'KdTree' from a list of data points using a
-- user-specified squared distance function.
--
-- Average time complexity: /O(n * log(n))/ for /n/ data points.
--
-- Worse case space complexity: /O(n)/ for /n/ data points.
--
-- Throws an error if given an empty list of data points.
buildKdTreeWithDistFn :: Real a => PointAsListFn a p
                                   -> SquaredDistanceFn a p
                                   -> [p]
                                   -> KdTree a p
buildKdTreeWithDistFn _ _ [] = error "KdTree must be built with a non-empty list."
buildKdTreeWithDistFn pointAsList distSqr ps =
  KdTree $ KDM.buildKdMapWithDistFn pointAsList distSqr $ zip ps $ repeat ()

-- | Given a 'KdTree' and a query point, returns the nearest point
-- in the 'KdTree' to the query point.
--
-- Average time complexity: /O(log(n))/ for /n/ data points.
nearestNeighbor :: Real a => KdTree a p -> p -> p
nearestNeighbor (KdTree t) query = fst $ KDM.nearestNeighbor t query

-- | Given a 'KdTree', a query point, and a radius, returns all
-- points in the 'KdTree' that are within the given radius of the
-- query point.
--
-- TODO: time complexity.
nearNeighbors :: Real a => KdTree a p
                           -> a -- ^ radius
                           -> p -- ^ query point
                           -> [p] -- ^ list of points in tree with
                                  -- given radius of query point
nearNeighbors (KdTree t) radius query = map fst $ KDM.nearNeighbors t radius query

-- | Given a 'KdTree', a query point, and a number @k@, returns the
-- @k@ nearest points in the 'KdTree' to the query point.
--
-- TODO: time complexity.
kNearestNeighbors :: Real a => KdTree a p -> Int -> p -> [p]
kNearestNeighbors (KdTree t) k query = map fst $ KDM.kNearestNeighbors t k query

-- | Returns a list of all the points in the 'KdTree'.
--
-- Time complexity: /O(n)/ for /n/ data points.
points :: KdTree a p -> [p]
points (KdTree t) = KDM.keys t

-- | Returns the number of elements in the 'KdTree'.
--
-- Time complexity: /O(1)/
size :: KdTree a p -> Int
size (KdTree t) = KDM.size t
