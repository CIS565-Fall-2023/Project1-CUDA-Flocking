#define GLM_FORCE_CUDA
#include <stdio.h>
#include <cuda.h>
#include <cmath>
#include <glm/glm.hpp>
#include "utilityCore.hpp"
#include "kernel.h"
#include <thrust/device_vector.h>
#include <thrust/scan.h>

// LOOK-2.1 potentially useful for doing grid-based neighbor search
#ifndef imax
#define imax( a, b ) ( ((a) > (b)) ? (a) : (b) )
#endif

#ifndef imin
#define imin( a, b ) ( ((a) < (b)) ? (a) : (b) )
#endif

#define checkCUDAErrorWithLine(msg) checkCUDAError(msg, __LINE__)

/**
* Check for CUDA errors; print and exit if there was a problem.
*/
void checkCUDAError(const char *msg, int line = -1) {
  cudaError_t err = cudaGetLastError();
  if (cudaSuccess != err) {
    if (line >= 0) {
      fprintf(stderr, "Line %d: ", line);
    }
    fprintf(stderr, "Cuda error: %s: %s.\n", msg, cudaGetErrorString(err));
    exit(EXIT_FAILURE);
  }
}


/*****************
* Configuration *
*****************/

/*! Block size used for CUDA kernel launch. */
#define blockSize 256

// LOOK-1.2 Parameters for the boids algorithm.
// These worked well in our reference implementation.
#define rule1Distance 5.0f
#define rule2Distance 3.0f
#define rule3Distance 5.0f

#define rule1Scale 0.01f
#define rule2Scale 0.1f
#define rule3Scale 0.05f

#define maxSpeed 1.0f

/*! Size of the starting area in simulation space. */
#define scene_scale 100.0f
/*! Size of the grid equals to max rule distance. */
#define SINGLE_MAX_DISTANCE_GRID 0


/***********************************************
* Kernel state (pointers are device pointers) *
***********************************************/

int numObjects;
dim3 threadsPerBlock(blockSize);

// LOOK-1.2 - These buffers are here to hold all your boid information.
// These get allocated for you in Boids::initSimulation.
// Consider why you would need two velocity buffers in a simulation where each
// boid cares about its neighbors' velocities.
// These are called ping-pong buffers.
glm::vec3 *dev_pos;
glm::vec3 *dev_vel1;
glm::vec3 *dev_vel2;

// LOOK-2.1 - these are NOT allocated for you. You'll have to set up the thrust
// pointers on your own too.  

// For efficient sorting and the uniform grid. These should always be parallel.
int *dev_particleArrayIndices; // What index in dev_pos and dev_velX represents this particle?
int *dev_particleGridIndices; // What grid cell is this particle in?
// needed for use with thrust
thrust::device_ptr<int> dev_thrust_particleArrayIndices;
thrust::device_ptr<int> dev_thrust_particleGridIndices;

int *dev_gridCellStartIndices; // What part of dev_particleArrayIndices belongs
int *dev_gridCellEndIndices;   // to this cell?
int* dev_gridCellPartitions;
int* dev_gridCellPartitionsPrefixSum;
int* dev_B0start;
int* dev_B0offset;
int B0_size=0;

__device__ unsigned int maxNumParticlesInGrid = 0;

// TODO-2.3 - consider what additional buffers you might need to reshuffle
// the position and velocity data to be coherent within cells.
glm::vec3* dev_pos_reordered;
glm::vec3* dev_vel1_reordered;
glm::vec3* dev_vel2_reordered;
// LOOK-2.1 - Grid parameters based on simulation parameters.
// These are automatically computed for you in Boids::initSimulation
int gridCellCount;
int gridSideCount;
float gridCellWidth;
float gridInverseCellWidth;
glm::vec3 gridMinimum;

/******************
* initSimulation *
******************/

__host__ __device__ unsigned int hash(unsigned int a) {
  a = (a + 0x7ed55d16) + (a << 12);
  a = (a ^ 0xc761c23c) ^ (a >> 19);
  a = (a + 0x165667b1) + (a << 5);
  a = (a + 0xd3a2646c) ^ (a << 9);
  a = (a + 0xfd7046c5) + (a << 3);
  a = (a ^ 0xb55a4f09) ^ (a >> 16);
  return a;
}

/**
* LOOK-1.2 - this is a typical helper function for a CUDA kernel.
* Function for generating a random vec3.
*/
__host__ __device__ glm::vec3 generateRandomVec3(float time, int index) {
  thrust::default_random_engine rng(hash((int)(index * time)));
  thrust::uniform_real_distribution<float> unitDistrib(-1, 1);

  return glm::vec3((float)unitDistrib(rng), (float)unitDistrib(rng), (float)unitDistrib(rng));
}

/**
* LOOK-1.2 - This is a basic CUDA kernel.
* CUDA kernel for generating boids with a specified mass randomly around the star.
*/
__global__ void kernGenerateRandomPosArray(int time, int N, glm::vec3 * arr, float scale) {
  int index = (blockIdx.x * blockDim.x) + threadIdx.x;
  if (index < N) {
    glm::vec3 rand = generateRandomVec3(time, index);
    arr[index].x = scale * rand.x;
    arr[index].y = scale * rand.y;
    arr[index].z = scale * rand.z;
  }
}

/**
* Initialize memory, update some globals
*/
void Boids::initSimulation(int N) {
  numObjects = N;
  dim3 fullBlocksPerGrid((N + blockSize - 1) / blockSize);

  // LOOK-1.2 - This is basic CUDA memory management and error checking.
  // Don't forget to cudaFree in  Boids::endSimulation.
  cudaMalloc((void**)&dev_pos, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_pos failed!");

  cudaMalloc((void**)&dev_vel1, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_vel1 failed!");

  cudaMalloc((void**)&dev_vel2, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_vel2 failed!");

  // LOOK-1.2 - This is a typical CUDA kernel invocation.
  kernGenerateRandomPosArray<<<fullBlocksPerGrid, blockSize>>>(1, numObjects,
    dev_pos, scene_scale);
  checkCUDAErrorWithLine("kernGenerateRandomPosArray failed!");

  float maxDistance = std::max(std::max(rule1Distance, rule2Distance), rule3Distance);
  // LOOK-2.1 computing grid params
#if SINGLE_MAX_DISTANCE_GRID
  gridCellWidth = 1.0f * maxDistance;
#else
  gridCellWidth = 2.0f * maxDistance;
#endif
  int halfSideCount = (scene_scale / gridCellWidth) + 1;
  gridSideCount = 2 * halfSideCount;

  gridCellCount = gridSideCount * gridSideCount * gridSideCount;
  gridInverseCellWidth = 1.0f / gridCellWidth;
  float halfGridWidth = gridCellWidth * halfSideCount;
  gridMinimum.x -= halfGridWidth;
  gridMinimum.y -= halfGridWidth;
  gridMinimum.z -= halfGridWidth;

  // TODO-2.1 TODO-2.3 - Allocate additional buffers here.
  cudaMalloc((void**)&dev_particleArrayIndices, N * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_particleArrayIndices failed!");
  cudaMalloc((void**)&dev_particleGridIndices, N * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_particleGridIndices failed!");
  cudaMalloc((void**)&dev_gridCellStartIndices, gridCellCount * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_gridCellStartIndices failed!");
  cudaMalloc((void**)&dev_gridCellEndIndices, gridCellCount * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_gridCellEndIndices failed!");
  dev_thrust_particleGridIndices = thrust::device_ptr<int>(dev_particleGridIndices);
  dev_thrust_particleArrayIndices = thrust::device_ptr<int>(dev_particleArrayIndices);
  cudaMalloc((void**)&dev_pos_reordered, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_pos_reordered failed!");
  cudaMalloc((void**)&dev_vel1_reordered, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_vel1_reordered failed!");
  cudaMalloc((void**)&dev_vel2_reordered, N * sizeof(glm::vec3));
  checkCUDAErrorWithLine("cudaMalloc dev_vel2_reordered failed!");

  cudaMalloc((void**)&dev_gridCellPartitions, gridCellCount * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_gridCellPartitions failed!");
  cudaMalloc((void**)&dev_gridCellPartitionsPrefixSum, gridCellCount * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_gridCellPartitionsPrefixSum failed!");

  B0_size = gridCellCount;

  cudaMalloc((void**)&dev_B0start, B0_size * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_B0start failed!");
  cudaMalloc((void**)&dev_B0offset, B0_size * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_B0offset failed!");

  int nil = 0;
  cudaMemcpyToSymbol(maxNumParticlesInGrid, &nil, sizeof(int));
  checkCUDAErrorWithLine("cudaMemcpyToSymbol maxNumParticlesInGrid failed!");

  cudaDeviceProp devProp;
  cudaGetDeviceProperties(&devProp, 0);
  std::cout << "CUDA device max shared memory per block:" << devProp.sharedMemPerBlock<<std::endl;

  cudaDeviceSetSharedMemConfig(cudaSharedMemBankSizeFourByte);
  checkCUDAErrorWithLine("cudaDeviceSetSharedMemConfig cudaSharedMemBankSizeFourByte failed!");
  cudaDeviceSynchronize();

}


/******************
* copyBoidsToVBO *
******************/

/**
* Copy the boid positions into the VBO so that they can be drawn by OpenGL.
*/
__global__ void kernCopyPositionsToVBO(int N, glm::vec3 *pos, float *vbo, float s_scale) {
  int index = threadIdx.x + (blockIdx.x * blockDim.x);

  float c_scale = -1.0f / s_scale;

  if (index < N) {
    vbo[4 * index + 0] = pos[index].x * c_scale;
    vbo[4 * index + 1] = pos[index].y * c_scale;
    vbo[4 * index + 2] = pos[index].z * c_scale;
    vbo[4 * index + 3] = 1.0f;
  }
}

__global__ void kernCopyVelocitiesToVBO(int N, glm::vec3 *vel, float *vbo, float s_scale) {
  int index = threadIdx.x + (blockIdx.x * blockDim.x);

  if (index < N) {
    vbo[4 * index + 0] = vel[index].x + 0.3f;
    vbo[4 * index + 1] = vel[index].y + 0.3f;
    vbo[4 * index + 2] = vel[index].z + 0.3f;
    vbo[4 * index + 3] = 1.0f;
  }
}

/**
* Wrapper for call to the kernCopyboidsToVBO CUDA kernel.
*/
void Boids::copyBoidsToVBO(float *vbodptr_positions, float *vbodptr_velocities) {
  dim3 fullBlocksPerGrid((numObjects + blockSize - 1) / blockSize);

  kernCopyPositionsToVBO << <fullBlocksPerGrid, blockSize >> >(numObjects, dev_pos, vbodptr_positions, scene_scale);
  kernCopyVelocitiesToVBO << <fullBlocksPerGrid, blockSize >> >(numObjects, dev_vel1, vbodptr_velocities, scene_scale);

  checkCUDAErrorWithLine("copyBoidsToVBO failed!");

  cudaDeviceSynchronize();
}


/******************
* stepSimulation *
******************/

/**
* LOOK-1.2 You can use this as a helper for kernUpdateVelocityBruteForce.
* __device__ code can be called from a __global__ context
* Compute the new velocity on the body with index `iSelf` due to the `N` boids
* in the `pos` and `vel` arrays.
*/
__device__ glm::vec3 computeVelocityChange(int N, int iSelf, const glm::vec3 *pos, const glm::vec3 *vel) {
  // Rule 1: boids fly towards their local perceived center of mass, which excludes themselves
  // Rule 2: boids try to stay a distance d away from each other
  // Rule 3: boids try to match the speed of surrounding boids
    glm::vec3 percived_center = glm::vec3(0);
    glm::vec3 v = vel[iSelf];
    int num_neighbours = 0;
    glm::vec3 percived_velocity = glm::vec3(0);
    glm::vec3 c = glm::vec3(0);
    for (int i = 0; i < N; i++)
    {
        float dist = glm::distance(pos[i], pos[iSelf]);
        if (i != iSelf && dist < rule1Distance)//rule1Distance==rule3Distance
        {
            num_neighbours++;
            percived_velocity += vel[i];
            percived_center += pos[i];
            if (dist < rule2Distance)
            {
                c -= (pos[i] - pos[iSelf]);
            }
        }
    }
    if (num_neighbours)
    {
        percived_center /= num_neighbours;
        v += (percived_center - pos[iSelf]) * rule1Scale;
        v += percived_velocity * rule3Scale / (float)num_neighbours;
        v += c * rule2Scale;
    }    
  return v;
}

/**
* TODO-1.2 implement basic flocking
* For each of the `N` bodies, update its position based on its current velocity.
*/
__global__ void kernUpdateVelocityBruteForce(int N, glm::vec3 *pos,
  glm::vec3 *vel1, glm::vec3 *vel2) {
  // Compute a new velocity based on pos and vel1
  // Clamp the speed
  // Record the new velocity into vel2. Question: why NOT vel1?
    int i = threadIdx.x + (blockIdx.x * blockDim.x);
    if (i >= N) {
        return;
    }
    vel2[i] = glm::clamp(computeVelocityChange(N, i, pos, vel1), -maxSpeed, maxSpeed);
}

/**
* LOOK-1.2 Since this is pretty trivial, we implemented it for you.
* For each of the `N` bodies, update its position based on its current velocity.
*/
__global__ void kernUpdatePos(int N, float dt, glm::vec3 *pos, glm::vec3 *vel) {
  // Update position by velocity
  int index = threadIdx.x + (blockIdx.x * blockDim.x);
  if (index >= N) {
    return;
  }
  glm::vec3 thisPos = pos[index];
  thisPos += vel[index] * dt;

  // Wrap the boids around so we don't lose them
  thisPos.x = thisPos.x < -scene_scale ? scene_scale : thisPos.x;
  thisPos.y = thisPos.y < -scene_scale ? scene_scale : thisPos.y;
  thisPos.z = thisPos.z < -scene_scale ? scene_scale : thisPos.z;

  thisPos.x = thisPos.x > scene_scale ? -scene_scale : thisPos.x;
  thisPos.y = thisPos.y > scene_scale ? -scene_scale : thisPos.y;
  thisPos.z = thisPos.z > scene_scale ? -scene_scale : thisPos.z;

  pos[index] = thisPos;
}

// LOOK-2.1 Consider this method of computing a 1D index from a 3D grid index.
// LOOK-2.3 Looking at this method, what would be the most memory efficient
//          order for iterating over neighboring grid cells?
//          for(x)
//            for(y)
//             for(z)? Or some other order?
__device__ int gridIndex3Dto1D(int x, int y, int z, int gridResolution) {
  return x + y * gridResolution + z * gridResolution * gridResolution;
}

__global__ void kernComputeIndices(int N, int gridResolution,
  glm::vec3 gridMin, float inverseCellWidth,
  glm::vec3 *pos, int* indices, int* gridIndices) {
    // TODO-2.1
    // - Label each boid with the index of its grid cell.
    // - Set up a parallel array of integer indices as pointers to the actual
    //   boid data in pos and vel1/vel2
    int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= N) return;
    indices[index] = index;
    glm::vec3 fidx = (pos[index] - gridMin) * inverseCellWidth;
    gridIndices[index] = gridIndex3Dto1D((int)fidx.x, (int)fidx.y, (int)fidx.z, gridResolution);
}

__global__ void kernComputeMortonCodeNaive(int N, int gridResolution,
    glm::vec3 gridMin, float inverseCellWidth,
    glm::vec3* pos, int* indices, uint64_t* zIndices) {
    int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= N) return;
    indices[index] = index;
    glm::vec3 fidx = (pos[index] - gridMin) * inverseCellWidth;
    uint64_t x = fidx.x, y = fidx.y, z = fidx.z;
    uint64_t zidx = 0;
    for (int i = 0; i < 21; i++)
    {
        zidx |= (x & 1) << (i * 3);
        zidx |= (y & 1) << (i * 3 + 1);
        zidx |= (z & 1) << (i * 3 + 2);
        x >>= 1; y >>= 1; z >>= 1;
    }
    zIndices[index] = zidx;
}

// LOOK-2.1 Consider how this could be useful for indicating that a cell
//          does not enclose any boids
__global__ void kernResetIntBuffer(int N, int* intBuffer, int value) {
  int index = (blockIdx.x * blockDim.x) + threadIdx.x;
  if (index < N) {
    intBuffer[index] = value;
  }
}

__global__ void kernIdentifyCellStartEnd(int N, int* particleGridIndices,
    int* gridCellStartIndices, int* gridCellEndIndices) {
  // TODO-2.1
  // Identify the start point of each cell in the gridIndices array.
  // This is basically a parallel unrolling of a loop that goes
  // "this index doesn't match the one before it, must be a new cell!"
    int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= N) return;
    if (index == 0)
    {
        gridCellStartIndices[particleGridIndices[index]] = index;
    }
    else
    {
        if (particleGridIndices[index - 1] != particleGridIndices[index])
        {
            gridCellEndIndices[particleGridIndices[index - 1]] = index;
            gridCellStartIndices[particleGridIndices[index]] = index;
        }
        if (index == N - 1)
        {
            gridCellEndIndices[particleGridIndices[index]] = index + 1;
        }
    }
}

__global__ void kernIdentifyMaxNumParticlesAndPartitionsInGrid(int N, int* gridCellStartIndices, int* gridCellEndIndices, int* partitionsForGrid)
{
    int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    __shared__ int blk_sz;
    if (threadIdx.x == 0) blk_sz = 0;
    __syncthreads();
    if (index < N)
    {
        int localsz = gridCellEndIndices[index] - gridCellStartIndices[index];
        atomicMax(&blk_sz, localsz);
        partitionsForGrid[index] = (localsz + blockSize - 1) / blockSize;
    }
    __syncthreads();
    if(threadIdx.x == 0)
        atomicMax(&maxNumParticlesInGrid, blk_sz);
}

__global__ void kernCompactArray(int N,int* gridCellPartitions, int* gridCellPartitionsPrefixSum,int* B0start,int* B0offset)
{
    int index = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (index >= N) return;
    int partitionSize = gridCellPartitions[index];
    if (partitionSize)
    {
        int b0idx = gridCellPartitionsPrefixSum[index];
        for (int i = 0; i < partitionSize; i++)
        {
            B0start[b0idx + i] = index;
            B0offset[b0idx + i] = i;
        }
    }
}

__global__ void kernUpdateVelNeighborSearchScattered(
  int N, int gridResolution, glm::vec3 gridMin,
  float inverseCellWidth, float cellWidth,
    int* gridCellStartIndices, int*gridCellEndIndices,
    int* particleArrayIndices,
  glm::vec3 *pos, glm::vec3 *vel1, glm::vec3 *vel2) {
    int selfIndex = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (selfIndex >= N) return;
  // TODO-2.1 - Update a boid's velocity using the uniform grid to reduce
  // the number of boids that need to be checked.
  // - Identify the grid cell that this particle is in
    glm::vec3 fidx = (pos[selfIndex] - gridMin) * inverseCellWidth;
    glm::ivec3 idx = glm::floor(fidx);
    glm::vec3 v = vel1[selfIndex];
    int num_neighbours = 0;
    glm::vec3 percived_velocity = glm::vec3(0);
    glm::vec3 percived_center = glm::vec3(0);
    glm::vec3 c = glm::vec3(0);
    // - Identify which cells may contain neighbors. This isn't always 8.
    // - For each cell, read the start/end indices in the boid pointer array.
    // - Access each boid in the cell and compute velocity change from
    //   the boids rules, if this boid is within the neighborhood distance.
#if SINGLE_MAX_DISTANCE_GRID
    for(int z=-1;z<=1;z++)
        for (int y = -1; y <= 1; y++)
            for (int x = -1; x <= 1; x++)
            {
                int nx = idx.x + x, ny = idx.y + y, nz = idx.z + z;
                if (nx < 0 || nx >= gridResolution || ny < 0 || ny >= gridResolution || nz < 0 || nz >= gridResolution)
                {
                    continue;
                }
                int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
                if (gridCellStartIndices[flattenedCellIdx]>=0)
                {
                    for (int arrayIdx = gridCellStartIndices[flattenedCellIdx]; arrayIdx != gridCellEndIndices[flattenedCellIdx]; arrayIdx++)
                    {
                        int other = particleArrayIndices[arrayIdx];
                        float dist = glm::distance(pos[selfIndex], pos[other]);
                        if (other != selfIndex && dist < rule1Distance)//assume rule1Distance==rule3Distance
                        {
                            num_neighbours++;
                            percived_velocity += vel1[other];
                            percived_center += pos[other];
                            if (dist < rule2Distance)
                            {
                                c -= (pos[other] - pos[selfIndex]);
                            }
                        }
                    }
                }
            }
#else
    glm::vec3 tmp = fidx - glm::floor(fidx);
    int dx = tmp.x > 0.5 ? 1 : -1;
    int dy = tmp.y > 0.5 ? 1 : -1;
    int dz = tmp.z > 0.5 ? 1 : -1;
    for(int z = 0;z < 2; z++)
        for(int y = 0;y < 2; y++)
            for (int x = 0; x < 2; x++)
            {
                int nx = idx.x + x * dx;
                int ny = idx.y + y * dy;
                int nz = idx.z + z * dz;
                if (nx < 0 || nx >= gridResolution || ny < 0 || ny >= gridResolution || nz < 0 || nz >= gridResolution)
                {
                    continue;
                }
                int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
                if (gridCellStartIndices[flattenedCellIdx]>=0)
                {
                    for (int arrayIdx = gridCellStartIndices[flattenedCellIdx]; arrayIdx != gridCellEndIndices[flattenedCellIdx]; arrayIdx++)
                    {
                        int other = particleArrayIndices[arrayIdx];
                        float dist = glm::distance(pos[selfIndex], pos[other]);
                        if (other != selfIndex && dist <= rule1Distance)//assume rule1Distance==rule3Distance
                        {
                            num_neighbours++;
                            percived_velocity += vel1[other];
                            percived_center += pos[other];
                            if (dist <= rule2Distance)
                            {
                                c -= (pos[other] - pos[selfIndex]);
                            }
                        }
                    }
                }
            }
#endif
    if (num_neighbours)
    {
        percived_center /= (num_neighbours);
        v += (percived_center - pos[selfIndex]) * rule1Scale;
        v += percived_velocity * rule3Scale / ((float)num_neighbours);
        v += c * rule2Scale;
    }
  // - Clamp the speed change before putting the new speed in vel2
    vel2[selfIndex] = glm::clamp(v, -maxSpeed, maxSpeed);
}

__global__ void kernShufflePosAndVel1(int N, int* particleArrayIndices, glm::vec3* pos, glm::vec3* vel, glm::vec3* pos_s, glm::vec3* vel_s)
{
    int i = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (i >= N) return;
    pos_s[i] = pos[particleArrayIndices[i]];
    vel_s[i] = vel[particleArrayIndices[i]];
}

__global__ void kernUnshuffleVel2(int N, int* particleArrayIndices, glm::vec3* vel2_s, glm::vec3* vel2)
{
    int i = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (i >= N) return;
    vel2[particleArrayIndices[i]] = vel2_s[i];
}

__global__ void kernUpdateVelNeighborSearchCoherent(
  int N, int gridResolution, glm::vec3 gridMin,
  float inverseCellWidth, float cellWidth,
    int*gridCellStartIndices, int*gridCellEndIndices,
  glm::vec3 *pos, glm::vec3 *vel1, glm::vec3 *vel2) {
    int selfIndex = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (selfIndex >= N) return;
  // TODO-2.3 - This should be very similar to kernUpdateVelNeighborSearchScattered,
  // except with one less level of indirection.
  // This should expect gridCellStartIndices and gridCellEndIndices to refer
  // directly to pos and vel1.
  // - Identify the grid cell that this particle is in
    glm::vec3 fidx = (pos[selfIndex] - gridMin) * inverseCellWidth;
    glm::ivec3 idx = fidx;
    glm::vec3 tmp = fidx - glm::floor(fidx);
    int dx = tmp.x > 0.5 ? 1 : -1, dy = tmp.y > 0.5 ? 1 : -1, dz = tmp.z > 0.5 ? 1 : -1;

    glm::vec3 v = vel1[selfIndex];
    int num_neighbours = 0;
    glm::vec3 percived_velocity = glm::vec3(0);
    glm::vec3 percived_center = glm::vec3(0);
    glm::vec3 c = glm::vec3(0);
  // - Identify which cells may contain neighbors. This isn't always 8.
  // - For each cell, read the start/end indices in the boid pointer array.
  //   DIFFERENCE: For best results, consider what order the cells should be
  //   checked in to maximize the memory benefits of reordering the boids data.
  // - Access each boid in the cell and compute velocity change from
  //   the boids rules, if this boid is within the neighborhood distance.
#if SINGLE_MAX_DISTANCE_GRID
    for (int z = -1; z <= 1; z++)
        for (int y = -1; y <= 1; y++)
            for (int x = -1; x <= 1; x++)
            {
                int nx = idx.x + x, ny = idx.y + y, nz = idx.z + z;
                if (nx < 0 || nx >= gridResolution || ny < 0 || ny >= gridResolution || nz < 0 || nz >= gridResolution)
                {
                    continue;
                }
                int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
                if (gridCellStartIndices[flattenedCellIdx]>=0)
                {
                    for (int other = gridCellStartIndices[flattenedCellIdx]; other != gridCellEndIndices[flattenedCellIdx]; other++)
                    {
                        float dist = glm::distance(pos[selfIndex], pos[other]);
                        if (other != selfIndex && dist < rule1Distance)//assume rule1Distance==rule3Distance
                        {
                            num_neighbours++;
                            percived_velocity += vel1[other];
                            percived_center += pos[other];
                            if (dist < rule2Distance)
                            {
                                c -= (pos[other] - pos[selfIndex]);
                            }
                        }
                    }
                }
            }
#else
    for (int z = 0; z < 2; z++)
        for (int y = 0; y < 2; y++)
            for (int x = 0; x < 2; x++)
            {
                int nx = idx.x + x * dx, ny = idx.y + y * dy, nz = idx.z + z * dz;
                if (nx < 0 || nx >= gridResolution || ny < 0 || ny >= gridResolution || nz < 0 || nz >= gridResolution)
                {
                    continue;
                }
                int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
                if (gridCellStartIndices[flattenedCellIdx] >= 0)
                {
                    for (int other = gridCellStartIndices[flattenedCellIdx]; other != gridCellEndIndices[flattenedCellIdx]; other++)
                    {
                        float dist = glm::distance(pos[selfIndex], pos[other]);
                        if (other != selfIndex && dist < rule1Distance)//assume rule1Distance==rule3Distance
                        {
                            num_neighbours++;
                            percived_velocity += vel1[other];
                            percived_center += pos[other];
                            if (dist < rule2Distance)
                            {
                                c -= (pos[other] - pos[selfIndex]);
                            }
                        }
                    }
                }
            }
#endif
  
    if (num_neighbours)
    {
        percived_center /= num_neighbours;
        v += (percived_center - pos[selfIndex]) * rule1Scale;
        v += percived_velocity * rule3Scale / (float)num_neighbours;
        v += c * rule2Scale;
    }
  // - Clamp the speed change before putting the new speed in vel2
    vel2[selfIndex] = glm::clamp(v, -maxSpeed, maxSpeed);
}

__global__ void kernUpdateVelNeighborSearchCoherentGridLoopingOptimization(
    int N, int gridResolution, glm::vec3 gridMin,
    float inverseCellWidth, float cellWidth,
    int* gridCellStartIndices, int* gridCellEndIndices,
    glm::vec3* pos, glm::vec3* vel1, glm::vec3* vel2) {
    int selfIndex = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (selfIndex >= N) return;

    glm::vec3 fidxmi = glm::clamp((pos[selfIndex] - glm::vec3(rule1Distance) - gridMin) * inverseCellWidth, (float)0, (float)gridResolution - 1);
    glm::vec3 fidxmx = glm::clamp((pos[selfIndex] + glm::vec3(rule1Distance) - gridMin) * inverseCellWidth, (float)0, (float)gridResolution - 1);
    glm::ivec3 mi = fidxmi, mx = fidxmx;

    glm::vec3 v = vel1[selfIndex];
    int num_neighbours = 0;
    glm::vec3 percived_velocity = glm::vec3(0);
    glm::vec3 percived_center = glm::vec3(0);
    glm::vec3 c = glm::vec3(0);

    for(int z=mi.z;z<=mx.z;z++)
        for(int y=mi.y;y<=mx.y;y++)
            for (int x = mi.x; x <= mx.x; x++)
            {
                int flattenedCellIdx = gridIndex3Dto1D(x, y, z, gridResolution);
                if (gridCellStartIndices[flattenedCellIdx] == -1) continue;
                for (int other = gridCellStartIndices[flattenedCellIdx]; other != gridCellEndIndices[flattenedCellIdx]; other++)
                {
                    float dist = glm::distance(pos[selfIndex], pos[other]);
                    if (other != selfIndex && dist < rule1Distance)//assume rule1Distance==rule3Distance
                    {
                        num_neighbours++;
                        percived_velocity += vel1[other];
                        percived_center += pos[other];
                        if (dist < rule2Distance)
                        {
                            c -= (pos[other] - pos[selfIndex]);
                        }
                    }
                }
            }

    if (num_neighbours)
    {
        percived_center /= num_neighbours;
        v += (percived_center - pos[selfIndex]) * rule1Scale;
        v += percived_velocity * rule3Scale / (float)num_neighbours;
        v += c * rule2Scale;
    }
    // - Clamp the speed change before putting the new speed in vel2
    vel2[selfIndex] = glm::clamp(v, -maxSpeed, maxSpeed);
}

#define NUM_COPY_THREADS 108

__global__ void kernUpdateVelNeighborSearchCoherentSharedMemoryOptimization(
    int N, int gridResolution,int gridMaxNumParticles, glm::vec3 gridMin,
    float inverseCellWidth, float cellWidth,
    const int* gridCellStartIndices, const int* gridCellEndIndices,const int* b0start, const int* b0offset,
    const glm::vec3* pos, const glm::vec3* vel1, glm::vec3* vel2) {
    int indexInGrid = b0offset[blockIdx.x] * blockSize + threadIdx.x;
    int selfFlattenedGridIdx = b0start[blockIdx.x];
    int particleIdxEnd = gridCellEndIndices[selfFlattenedGridIdx];
    int particleIdxStart = gridCellStartIndices[selfFlattenedGridIdx];
    int gridNumParticles = particleIdxEnd - particleIdxStart;
    
    
    glm::ivec3 gridIdx = glm::ivec3((selfFlattenedGridIdx % (gridResolution * gridResolution)) % gridResolution, (selfFlattenedGridIdx % (gridResolution * gridResolution)) / gridResolution, selfFlattenedGridIdx / (gridResolution * gridResolution));
    int localIndex = threadIdx.x;
    extern __shared__ glm::vec3 s[];
    
    if (localIndex < NUM_COPY_THREADS)
    {
        int w = localIndex / 27;
        int li = localIndex % 27;
        int x = (li % 9) % 3 - 1, y = (li % 9) / 3 - 1, z = li / 9 - 1;
        int nx = gridIdx.x + x, ny = gridIdx.y + y, nz = gridIdx.z + z;
        if (nx >= 0 || nx < gridResolution || ny >= 0 || ny < gridResolution || nz >= 0 || nz < gridResolution)
        {
            int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
            if (gridCellStartIndices[flattenedCellIdx] >= 0)
            {
                for (int other = gridCellStartIndices[flattenedCellIdx] + w, i = w; other < gridCellEndIndices[flattenedCellIdx]; other+= NUM_COPY_THREADS/27,i+= NUM_COPY_THREADS / 27)
                {
                    s[gridMaxNumParticles * li * 2 + i * 2] = pos[other];
                    s[gridMaxNumParticles * li * 2 + i * 2 + 1] = vel1[other];
                }
            }
        }
    }
    __syncthreads();
    if (indexInGrid < gridNumParticles)
    {
        // TODO-2.3 - This should be very similar to kernUpdateVelNeighborSearchScattered,
        // except with one less level of indirection.
        // This should expect gridCellStartIndices and gridCellEndIndices to refer
        // directly to pos and vel1.
        // - Identify the grid cell that this particle is in
        int selfIndex = particleIdxStart + b0offset[blockIdx.x] * blockSize + threadIdx.x;
        int blockOffset = indexInGrid * 2;
        int centerGridOffset = gridMaxNumParticles * (27/2) * 2;
        glm::vec3 currPos = s[centerGridOffset + blockOffset];
        glm::vec3 v = s[centerGridOffset + blockOffset + 1];
        int num_neighbours = 0;
        glm::vec3 percived_velocity = glm::vec3(0);
        glm::vec3 percived_center = glm::vec3(0);
        glm::vec3 c = glm::vec3(0);
        // - Identify which cells may contain neighbors. This isn't always 8.
        // - For each cell, read the start/end indices in the boid pointer array.
        //   DIFFERENCE: For best results, consider what order the cells should be
        //   checked in to maximize the memory benefits of reordering the boids data.
        // - Access each boid in the cell and compute velocity change from
        //   the boids rules, if this boid is within the neighborhood distance.
        for (int z = -1; z <= 1; z++)
            for (int y = -1; y <= 1; y++)
                for (int x = -1; x <= 1; x++)
                {
                    int nx = gridIdx.x + x, ny = gridIdx.y + y, nz = gridIdx.z + z;
                    if (nx < 0 || nx >= gridResolution || ny < 0 || ny >= gridResolution || nz < 0 || nz >= gridResolution)
                    {
                        continue;
                    }
                    int flattenedCellIdx = gridIndex3Dto1D(nx, ny, nz, gridResolution);
                    int smCellIdx = gridIndex3Dto1D(x + 1, y + 1, z + 1, 3);
                    if (gridCellStartIndices[flattenedCellIdx] >= 0)
                    {
                        for (int other = gridCellStartIndices[flattenedCellIdx],i=0; other != gridCellEndIndices[flattenedCellIdx]; other++,i++)
                        {
                            float dist = glm::distance(currPos, s[gridMaxNumParticles * smCellIdx * 2 + i * 2]);
                            if (other != selfIndex && dist < rule1Distance)//assume rule1Distance==rule3Distance
                            {
                                num_neighbours++;
                                percived_velocity += s[gridMaxNumParticles * smCellIdx * 2 + i * 2 + 1];
                                percived_center += s[gridMaxNumParticles * smCellIdx * 2 + i * 2];
                                if (dist < rule2Distance)
                                {
                                    c -= (s[gridMaxNumParticles * smCellIdx * 2 + i * 2] - currPos);
                                }
                            }
                        }
                    }
                }

        if (num_neighbours)
        {
            percived_center /= num_neighbours;
            v += (percived_center - currPos) * rule1Scale;
            v += percived_velocity * rule3Scale / (float)num_neighbours;
            v += c * rule2Scale;
        }
        // - Clamp the speed change before putting the new speed in vel2
        vel2[selfIndex] = glm::clamp(v, -maxSpeed, maxSpeed);
    }
}

/**
* Step the entire N-body simulation by `dt` seconds.
*/
void Boids::stepSimulationNaive(float dt) {
    int n = (numObjects + blockSize - 1) / blockSize;
  // TODO-1.2 - use the kernels you wrote to step the simulation forward in time.
    kernUpdateVelocityBruteForce << <n, blockSize >> > (numObjects, dev_pos, dev_vel1, dev_vel2);
    kernUpdatePos << <n, blockSize >> > (numObjects, dt, dev_pos, dev_vel2);
  // TODO-1.2 ping-pong the velocity buffers
    std::swap(dev_vel1, dev_vel2);
}

void Boids::stepSimulationScatteredGrid(float dt) {
    int n1 = (numObjects + blockSize - 1) / blockSize;
    int n2 = (gridCellCount + blockSize - 1) / blockSize;
  // TODO-2.1
  // Uniform Grid Neighbor search using Thrust sort.
  // In Parallel:
  // - label each particle with its array index as well as its grid index.
  //   Use 2x width grids.
    kernComputeIndices << < n1, blockSize >> > (numObjects, gridSideCount, gridMinimum, gridInverseCellWidth, dev_pos, dev_particleArrayIndices, dev_particleGridIndices);
  // - Unstable key sort using Thrust. A stable sort isn't necessary, but you
  //   are welcome to do a performance comparison.
    thrust::sort_by_key(dev_thrust_particleGridIndices, dev_thrust_particleGridIndices + numObjects, dev_thrust_particleArrayIndices);
  // - Naively unroll the loop for finding the start and end indices of each
  //   cell's data pointers in the array of boid indices
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellStartIndices, -1);
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellEndIndices, -1);
    kernIdentifyCellStartEnd << < n1, blockSize >> > (numObjects, dev_particleGridIndices, dev_gridCellStartIndices, dev_gridCellEndIndices);
  // - Perform velocity updates using neighbor search
    kernUpdateVelNeighborSearchScattered << < n1, blockSize >> > (numObjects, gridSideCount, gridMinimum, gridInverseCellWidth, gridCellWidth, dev_gridCellStartIndices, dev_gridCellEndIndices, dev_particleArrayIndices, dev_pos, dev_vel1, dev_vel2);
  // - Update positions
    kernUpdatePos << <n1, blockSize >> > (numObjects, dt, dev_pos, dev_vel2);
  // - Ping-pong buffers as needed
    std::swap(dev_vel1, dev_vel2);
}

void Boids::stepSimulationCoherentGrid(float dt) {
    int n1 = (numObjects + blockSize - 1) / blockSize;
    int n2 = (gridCellCount + blockSize - 1) / blockSize;
    int N = numObjects;
  // TODO-2.3 - start by copying Boids::stepSimulationNaiveGrid
  // Uniform Grid Neighbor search using Thrust sort on cell-coherent data.
  // In Parallel:
  // - Label each particle with its array index as well as its grid index.
  //   Use 2x width grids
    kernComputeIndices << < n1, blockSize >> > (N, gridSideCount, gridMinimum, gridInverseCellWidth, dev_pos, dev_particleArrayIndices, dev_particleGridIndices);
  // - Unstable key sort using Thrust. A stable sort isn't necessary, but you
  //   are welcome to do a performance comparison.
    thrust::sort_by_key(dev_thrust_particleGridIndices, dev_thrust_particleGridIndices + numObjects, dev_thrust_particleArrayIndices);
  // - Naively unroll the loop for finding the start and end indices of each
  //   cell's data pointers in the array of boid indices
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellStartIndices, -1);
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellEndIndices, -1);
    kernIdentifyCellStartEnd << < n1, blockSize >> > (N, dev_particleGridIndices, dev_gridCellStartIndices, dev_gridCellEndIndices);
  // - BIG DIFFERENCE: use the rearranged array index buffer to reshuffle all
  //   the particle data in the simulation array.
  //   CONSIDER WHAT ADDITIONAL BUFFERS YOU NEED
    kernShufflePosAndVel1 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_pos, dev_vel1, dev_pos_reordered, dev_vel1_reordered);
  // - Perform velocity updates using neighbor search
    kernUpdateVelNeighborSearchCoherent << < n1, blockSize >> > (N, gridSideCount, gridMinimum, gridInverseCellWidth, gridCellWidth, dev_gridCellStartIndices, dev_gridCellEndIndices, dev_pos_reordered, dev_vel1_reordered, dev_vel2_reordered);
    kernUnshuffleVel2 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_vel2_reordered, dev_vel2);
    // - Update positions
    kernUpdatePos << <n1, blockSize >> > (numObjects, dt, dev_pos, dev_vel2);
  // - Ping-pong buffers as needed. THIS MAY BE DIFFERENT FROM BEFORE.
    std::swap(dev_vel1, dev_vel2);
}

void Boids::stepSimulationCoherentGridLoopingOptimization(float dt) 
{
    int n1 = (numObjects + blockSize - 1) / blockSize;
    int n2 = (gridCellCount + blockSize - 1) / blockSize;
    int N = numObjects;
    // TODO-2.3 - start by copying Boids::stepSimulationNaiveGrid
    // Uniform Grid Neighbor search using Thrust sort on cell-coherent data.
    // In Parallel:
    // - Label each particle with its array index as well as its grid index.
    //   Use 2x width grids
    kernComputeIndices << < n1, blockSize >> > (N, gridSideCount, gridMinimum, gridInverseCellWidth, dev_pos, dev_particleArrayIndices, dev_particleGridIndices);
    // - Unstable key sort using Thrust. A stable sort isn't necessary, but you
    //   are welcome to do a performance comparison.
    thrust::device_ptr<int> dev_thrust_keys(dev_particleGridIndices);
    thrust::device_ptr<int> dev_thrust_values(dev_particleArrayIndices);
    thrust::sort_by_key(dev_thrust_keys, dev_thrust_keys + N, dev_thrust_values);
    // - Naively unroll the loop for finding the start and end indices of each
    //   cell's data pointers in the array of boid indices
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellStartIndices, -1);
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellEndIndices, -1);
    kernIdentifyCellStartEnd << < n1, blockSize >> > (N, dev_particleGridIndices, dev_gridCellStartIndices, dev_gridCellEndIndices);
    // - BIG DIFFERENCE: use the rearranged array index buffer to reshuffle all
    //   the particle data in the simulation array.
    //   CONSIDER WHAT ADDITIONAL BUFFERS YOU NEED
    kernShufflePosAndVel1 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_pos, dev_vel1, dev_pos_reordered, dev_vel1_reordered);
    // - Perform velocity updates using neighbor search
    kernUpdateVelNeighborSearchCoherentGridLoopingOptimization << < n1, blockSize >> > (N, gridSideCount, gridMinimum, gridInverseCellWidth, gridCellWidth, dev_gridCellStartIndices, dev_gridCellEndIndices, dev_pos_reordered, dev_vel1_reordered, dev_vel2_reordered);
    kernUnshuffleVel2 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_vel2_reordered, dev_vel2);
    // - Update positions
    kernUpdatePos << <n1, blockSize >> > (numObjects, dt, dev_pos, dev_vel2);
    // - Ping-pong buffers as needed. THIS MAY BE DIFFERENT FROM BEFORE.
    std::swap(dev_vel1, dev_vel2);
}

void Boids::stepSimulationCoherentGridSharedMemOptimization(float dt) {
    int n1 = (numObjects + blockSize - 1) / blockSize;
    int n2 = (gridCellCount + blockSize - 1) / blockSize;
    int N = numObjects;
    // TODO-2.3 - start by copying Boids::stepSimulationNaiveGrid
    // Uniform Grid Neighbor search using Thrust sort on cell-coherent data.
    // In Parallel:
    // - Label each particle with its array index as well as its grid index.
    //   Use 2x width grids
    kernComputeIndices << < n1, blockSize >> > (N, gridSideCount, gridMinimum, gridInverseCellWidth, dev_pos, dev_particleArrayIndices, dev_particleGridIndices);
    //checkCUDAErrorWithLine("kernComputeIndices failed!");
    // - Unstable key sort using Thrust. A stable sort isn't necessary, but you
    //   are welcome to do a performance comparison.
    thrust::sort_by_key(dev_thrust_particleGridIndices, dev_thrust_particleGridIndices + numObjects, dev_thrust_particleArrayIndices);
    // - Naively unroll the loop for finding the start and end indices of each
    //   cell's data pointers in the array of boid indices
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellStartIndices, -1);
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellEndIndices, -1);
    kernIdentifyCellStartEnd << < n1, blockSize >> > (N, dev_particleGridIndices, dev_gridCellStartIndices, dev_gridCellEndIndices);
    kernResetIntBuffer << < n2, blockSize >> > (gridCellCount, dev_gridCellPartitions, 0);
    kernIdentifyMaxNumParticlesAndPartitionsInGrid << < n2, blockSize >> > (gridCellCount, dev_gridCellStartIndices, dev_gridCellEndIndices, dev_gridCellPartitions);
    thrust::device_ptr<int> dev_thrust_gridcellpartition(dev_gridCellPartitions);
    thrust::device_ptr<int> dev_thrust_gridcellpartitionprefixsum(dev_gridCellPartitionsPrefixSum);
    thrust::exclusive_scan(dev_thrust_gridcellpartition, dev_thrust_gridcellpartition + gridCellCount, dev_gridCellPartitionsPrefixSum);
    //checkCUDAErrorWithLine("exclusive_scan failed!");
    int b0size,lastPos,lastSize;
    int maxNumParticles;
    cudaMemcpyFromSymbol(&maxNumParticles, maxNumParticlesInGrid, sizeof(int));
    int nil = 0;
    cudaMemcpyToSymbol(maxNumParticlesInGrid, &nil, sizeof(int));
    cudaMemcpy(&lastPos, dev_gridCellPartitionsPrefixSum + gridCellCount - 1, sizeof(int), cudaMemcpyDeviceToHost);
    cudaMemcpy(&lastSize, dev_gridCellPartitions + gridCellCount - 1, sizeof(int), cudaMemcpyDeviceToHost);
    b0size = lastPos + lastSize;
    if (b0size > B0_size)
    {
        B0_size = b0size;
        cudaFree(dev_B0start);
        cudaFree(dev_B0offset);
        cudaMalloc((void**)&dev_B0start, b0size * sizeof(int));
        checkCUDAErrorWithLine("cudaMalloc dev_B0start failed!");
        cudaMalloc((void**)&dev_B0offset, b0size * sizeof(int));
        checkCUDAErrorWithLine("cudaMalloc dev_B0offset failed!");
    }
    kernCompactArray << <n2, blockSize >> > (gridCellCount, dev_gridCellPartitions, dev_gridCellPartitionsPrefixSum, dev_B0start, dev_B0offset);
    uint64_t sharedMemSize = (uint64_t)maxNumParticles * 27 * sizeof(glm::vec3) * 2;
    // - BIG DIFFERENCE: use the rearranged array index buffer to reshuffle all
    //   the particle data in the simulation array.
    //   CONSIDER WHAT ADDITIONAL BUFFERS YOU NEED
    kernShufflePosAndVel1 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_pos, dev_vel1, dev_pos_reordered, dev_vel1_reordered);
    // - Perform velocity updates using neighbor search
    kernUpdateVelNeighborSearchCoherentSharedMemoryOptimization << < b0size, blockSize, sharedMemSize>> > (b0size, gridSideCount, maxNumParticles, gridMinimum, gridInverseCellWidth, gridCellWidth, dev_gridCellStartIndices, dev_gridCellEndIndices, dev_B0start, dev_B0offset, dev_pos_reordered, dev_vel1_reordered, dev_vel2_reordered);
    checkCUDAErrorWithLine("kernUpdateVelNeighborSearchCoherentSharedMemoryOptimization failed!");
    kernUnshuffleVel2 << < n1, blockSize >> > (N, dev_particleArrayIndices, dev_vel2_reordered, dev_vel2);
    // - Update positions
    kernUpdatePos << <n1, blockSize >> > (numObjects, dt, dev_pos, dev_vel2);
    // - Ping-pong buffers as needed. THIS MAY BE DIFFERENT FROM BEFORE.
    std::swap(dev_vel1, dev_vel2);
}

void Boids::endSimulation() {
  cudaFree(dev_vel1);
  cudaFree(dev_vel2);
  cudaFree(dev_pos);

  // TODO-2.1 TODO-2.3 - Free any additional buffers here.
  cudaFree(dev_particleArrayIndices);
  cudaFree(dev_particleGridIndices);
  cudaFree(dev_gridCellStartIndices);
  cudaFree(dev_gridCellEndIndices);
  cudaFree(dev_pos_reordered);
  cudaFree(dev_vel1_reordered);
  cudaFree(dev_vel2_reordered);
}

void Boids::unitTest() {
  // LOOK-1.2 Feel free to write additional tests here.

  // test unstable sort
  int *dev_intKeys;
  int *dev_intValues;
  int N = 10;

  std::unique_ptr<int[]>intKeys{ new int[N] };
  std::unique_ptr<int[]>intValues{ new int[N] };

  intKeys[0] = 0; intValues[0] = 0;
  intKeys[1] = 1; intValues[1] = 1;
  intKeys[2] = 0; intValues[2] = 2;
  intKeys[3] = 3; intValues[3] = 3;
  intKeys[4] = 0; intValues[4] = 4;
  intKeys[5] = 2; intValues[5] = 5;
  intKeys[6] = 2; intValues[6] = 6;
  intKeys[7] = 0; intValues[7] = 7;
  intKeys[8] = 5; intValues[8] = 8;
  intKeys[9] = 6; intValues[9] = 9;

  cudaMalloc((void**)&dev_intKeys, N * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_intKeys failed!");

  cudaMalloc((void**)&dev_intValues, N * sizeof(int));
  checkCUDAErrorWithLine("cudaMalloc dev_intValues failed!");

  dim3 fullBlocksPerGrid((N + blockSize - 1) / blockSize);

  std::cout << "before unstable sort: " << std::endl;
  for (int i = 0; i < N; i++) {
    std::cout << "  key: " << intKeys[i];
    std::cout << " value: " << intValues[i] << std::endl;
  }

  // How to copy data to the GPU
  cudaMemcpy(dev_intKeys, intKeys.get(), sizeof(int) * N, cudaMemcpyHostToDevice);
  cudaMemcpy(dev_intValues, intValues.get(), sizeof(int) * N, cudaMemcpyHostToDevice);

  // Wrap device vectors in thrust iterators for use with thrust.
  thrust::device_ptr<int> dev_thrust_keys(dev_intKeys);
  thrust::device_ptr<int> dev_thrust_values(dev_intValues);
  // LOOK-2.1 Example for using thrust::sort_by_key
  thrust::sort_by_key(dev_thrust_keys, dev_thrust_keys + N, dev_thrust_values);

  // How to copy data back to the CPU side from the GPU
  cudaMemcpy(intKeys.get(), dev_intKeys, sizeof(int) * N, cudaMemcpyDeviceToHost);
  cudaMemcpy(intValues.get(), dev_intValues, sizeof(int) * N, cudaMemcpyDeviceToHost);
  checkCUDAErrorWithLine("memcpy back failed!");

  std::cout << "after unstable sort: " << std::endl;
  for (int i = 0; i < N; i++) {
    std::cout << "  key: " << intKeys[i];
    std::cout << " value: " << intValues[i] << std::endl;
  }

  // cleanup
  cudaFree(dev_intKeys);
  cudaFree(dev_intValues);
  checkCUDAErrorWithLine("cudaFree failed!");
  return;
}
