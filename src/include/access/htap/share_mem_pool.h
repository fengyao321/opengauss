/*
 * Copyright (c) 2025 Huawei Technologies Co.,Ltd.
 *
 * openGauss is licensed under Mulan PSL v2.
 * You can use this software according to the terms and conditions of the Mulan PSL v2.
 * You may obtain a copy of Mulan PSL v2 at:
 *
 *          http://license.coscl.org.cn/MulanPSL2
 *
 * THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
 * EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
 * MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
 * See the Mulan PSL v2 for more details.
 * ---------------------------------------------------------------------------------------
 *
 * share_mem_pool.h
 *        routines to support DSS IMColStore
 *
 *
 * IDENTIFICATION
 *        src/include/access/htap/share_mem_pool.h
 *
 * ---------------------------------------------------------------------------------------
 */

#ifndef SHARE_MEM_POOL_H
#define SHARE_MEM_POOL_H
#include <vector>
#include "postgres.h"
#include "knl/knl_variable.h"
#include "storage/ubs_mem.h"

#define READ_WIRTE (PROT_READ | PROT_WRITE)
#define ONLY_READ (PROT_READ)
#define SHM_CHUNK_SIZE (128 * 1024 * 1024)  /* 128MB */
#define INVALID_SHM_CHUNK_NUMBER (-1)
#define IS_VALID_SHM_CHUNK_NUMBER(x) ((x) != INVALID_SHM_CHUNK_NUMBER)

template <typename T> class VectorList;

typedef struct {
    Size usedSize;
    int curCuNum;
    void* chunkPtr;
} SHMChunk;

typedef enum ShareMemErrorCode : uint16_t {
    UNMAP_SHAREMEM_ERROR = 5001,
    DELETE_SHAREMEM_ERROR
} SMErrorCode;

/*
* This class provides some API for dss imcstore share memory.
*/
class ShareMemoryPool : public BaseObject {
public:
    static void GetShmChunkName(char* chunkName, Oid relOid, int shmChunkNumber);
    void ShmChunkMmapAll(int shmChunksNum);
    void* CopyShareCUMem(_in_ char* localCUPtr, _in_ uint32 cuSize,
        _out_ uint32 *shmCUOffset, _out_ int *shmChunkNumber);
    void* LoadCUBuf(int shmChunkNumber, uint32 shmCUOffset, Size cuSize);
    void FreeCUMem(int shmChunkNumber, uint32 shmCUOffset, Size cuSize);
    int GetChunkNum();
    void Init(Oid relOid);
    void Destroy();
    int DestoryShmChunk();

    ShareMemoryPool();
    ~ShareMemoryPool();

private:
    int CreateNewShmChunk();
    int AllocateFreeShmChunk(Size alignCUSize);
    void* AllocateCUMem(_in_ Size alignCuSize, _out_ uint32 *shmCUOffset, _out_ int *shmChunkNumber);
    void* ShmChunkMmap(char *name);

    Oid m_relOid;
    int m_shmChunkNum;
    VectorList<SHMChunk>* m_shmChunks;
    pthread_rwlock_t m_shm_mutex;
};

#endif /* SHARE_MEM_POOL_H */