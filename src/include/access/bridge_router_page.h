/* -------------------------------------------------------------------------
 *
 * bridge_router_page.h
 *    Physical page layout definitions for the openGauss Bridge Router.
 *
 * Portions Copyright (c) 2026, openGauss Contributors
 *
 * IDENTIFICATION
 *    src/include/access/bridge_router_page.h
 *
 * -------------------------------------------------------------------------
 */

#ifndef BRIDGE_ROUTER_PAGE_H
#define BRIDGE_ROUTER_PAGE_H

#include "postgres.h"
#include "access/xlogdefs.h"
#include "storage/buf/bufpage.h"
#include "storage/item/itemptr.h"

#define BRIDGE_ROUTER_MAGIC            0x42525452 /* ASCII 'BRTR' */
#define BRIDGE_ROUTER_VERSION          1

#define BRIDGE_ROUTER_METAPAGE_BLKNO   0
#define BRIDGE_ROUTER_FIRST_LEAF_BLKNO 1

/* Page Flags */
#define BRIDGE_PAGE_META               0x0001
#define BRIDGE_PAGE_LEAF               0x0002
#define BRIDGE_PAGE_INTERNAL           0x0004
#define BRIDGE_PAGE_RIGHTMOST          0x0008

/*
 * Meta Page Data stored at Block 0 of the Bridge Router relation file
 */
typedef struct BridgeRouterMetaPageData {
    uint32          magic;                 /* BRIDGE_ROUTER_MAGIC */
    uint32          version;               /* Format version */
    BlockNumber     root_blkno;            /* Block number of the root page */
    BlockNumber     rightmost_leaf_blkno;  /* Block number of the rightmost leaf page */
    BlockNumber     leftmost_leaf_blkno;   /* Block number of the leftmost leaf page */
    uint16          tree_height;           /* Current height of the router B+ tree */
    uint16          reserved;              /* Alignment padding */
    uint64          total_entries;         /* Total number of active route entries */
    uint64          max_seq;               /* Highest sequence number appended */
} BridgeRouterMetaPageData;

typedef BridgeRouterMetaPageData *BridgeRouterMetaPage;

/*
 * Standard Page Header for all Leaf and Internal Pages (40 bytes MAXALIGN)
 */
typedef struct BridgeRouterPageHeaderData {
    XLogRecPtr      pd_lsn;        /* WAL LSN of last modification */
    uint16          pd_checksum;   /* Page checksum */
    uint16          pd_flags;      /* Page type flags (LEAF / INTERNAL / RIGHTMOST) */
    LocationIndex   pd_lower;      /* Offset to start of free space */
    LocationIndex   pd_upper;      /* Offset to end of free space */
    uint16          pd_item_count; /* Number of entries on this page */
    uint16          pd_level;      /* Tree level (0 for leaf, >= 1 for internal) */
    BlockNumber     pd_next_blk;   /* Block number of the right sibling page */
    BlockNumber     pd_prev_blk;   /* Block number of the left sibling page */
    uint64          pd_high_seq;   /* Maximum sequence number on this page */
} BridgeRouterPageHeaderData;

typedef BridgeRouterPageHeaderData *BridgeRouterPageHeader;
#define SizeOfBridgeRouterPageHeaderData (MAXALIGN(sizeof(BridgeRouterPageHeaderData)))

/*
 * Leaf Entry: strictly 14 bytes packed (8B BridgeSeqNo + 6B ItemPointerData)
 * Provides 582 entries per 8KB page!
 */
#pragma pack(push, 2)
typedef struct BridgeLeafEntry {
    uint64          seq;          /* 8-byte monotonic virtual sequence number */
    ItemPointerData tid;          /* 6-byte physical host tuple TID (Block + Offset) */
} BridgeLeafEntry;
#pragma pack(pop)

#define SizeOfBridgeLeafEntry (sizeof(BridgeLeafEntry))

/*
 * Internal Entry: strictly 12 bytes packed (8B child_min_seq + 4B child_blkno)
 */
#pragma pack(push, 2)
typedef struct BridgeInternalEntry {
    uint64          child_min_seq; /* 8-byte lowest sequence number in the child page */
    BlockNumber     child_blkno;   /* 4-byte block number of the child page */
} BridgeInternalEntry;
#pragma pack(pop)

#define SizeOfBridgeInternalEntry (sizeof(BridgeInternalEntry))

/* Maximum number of entries per 8KB page */
#define BRIDGE_ROUTER_MAX_LEAF_ENTRIES \
    ((uint16)((BLCKSZ - SizeOfBridgeRouterPageHeaderData) / SizeOfBridgeLeafEntry))

#define BRIDGE_ROUTER_MAX_INTERNAL_ENTRIES \
    ((uint16)((BLCKSZ - SizeOfBridgeRouterPageHeaderData) / SizeOfBridgeInternalEntry))

#endif /* BRIDGE_ROUTER_PAGE_H */
