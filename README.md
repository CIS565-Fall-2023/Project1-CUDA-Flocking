**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Licheng CAO
  * [LinkedIn](https://www.linkedin.com/in/licheng-cao-6a523524b/)
* Tested on: Windows 10, i7-10870H @ 2.20GHz 32GB, GTX 3060 6009MB

### Result (65536 Boids)
![boid](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/1cb4f564-45ab-450e-b207-078f50b25ec1)
### Analysis
* the number of boids (with/without visualization)
  * Figures 1 and 2 depict a clear trend: as the number of boids increases, the frames per second (FPS) decreases. This decline is primarily attributed to the growing number of boids that each thread must process. Among the various step methods, the naive method is the most affected by the number of boids, as it necessitates considering all boids within each thread. On the other hand, the scattered method significantly enhances performance by limiting the scope to boids in nearby grids, thereby reducing the number of boids each thread must handle. Additionally, in this method, I've implemented a specific order for searching the nearby grids to ensure contiguous grid access.
  * The coherent method provides a slight performance boost over the scattered method. It accomplishes this by rearranging the position and velocity arrays of boids in such a way that information for boids within the same grid is stored contiguously in memory. This optimization allows for faster retrieval of information when iterating over all boids within a single grid.
  * Figure1 average FPS/number of boids with visualization
  * ![avgFPS_numboidsV](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/33356f73-1b16-4cc2-91ac-24c927ba56ee)
  * Figure2 average FPS/number of boids without visualization
  * ![avgFPS_numboids](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/5f1a855f-b75f-411d-97f1-535e59112a31)
  * We observe that the average FPS is higher when visualization is disabled. As the number of boids increases, the disparity between FPS with and without visualization diminishes. This phenomenon occurs because the primary bottleneck affecting FPS is the GPU calculations when dealing with a large number of boids, whereas it becomes the drawing speed when dealing with a smaller number of boids.
  * Figure3 average FPS with/without visualization
  * ![FPS_V_NV](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/2a995a12-fa67-4af3-9318-a58f095da892)

* the blocksize and cell width
  * Table 1 and Figure 4 provide insights into the behavior of the average FPS. In the case of the naive method, we observe that the average FPS remains relatively consistent. However, for both the scattered and coherent methods, altering the block size from 32 to 64 leads to an increase in the average FPS, while changing it from 224 to 512 results in a decrease.
  * The increase in average FPS with the larger block size can be attributed to the block having more warps, allowing for smoother switching to hide the delay associated with accessing global data. Conversely, the decrease in average FPS with the smaller block size may stem from each Streaming Multiprocessor (SM) lacking sufficient Streaming Processors (SPs) to efficiently process threads in a single loop.
  * Modifying the cell width and increasing the number of blocks to check from 8 to 27 can have a notable impact on the performance of my implementation. In my approach, I introduce a jitter vector (vec3(-0.5)) to ensure that each boid within a grid only needs to search within nearby 8 blocks to locate all neighboring boids efficiently. Consequently, examining 27 blocks would introduce unnecessary computational overhead.
  * However, when we alter the cell width and block size, the outcomes may differ. A smaller cell width could result in a reduced bounding box for each boid, potentially decreasing the number of boids that each thread needs to inspect. This reduction in workload could, in turn, lead to improved performance.
  * Table1 average FPS/blocksize without visualization (number of boids: 524,288)
  * | blocksize | 32    | 64    | 96    | 128   | 160   |  192  |  224  | 512 |
    | :---:     | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
    | naiveFPS  | 0.323 | 0.454 | 0.452 | 0.458 | 0.449 | 0.455 | 0.457 |0.1326|
    | ScatteredFPS|129.62|174.728 | 181.97 | 181.566 | 179.985 | 181.666| 177.534 |166.941|
    |CoherentFPS|231.937|	270.333|	273.499|	270.334|	269.264	|269.608|	267.44|251.679|
  * Figure4 average FPS/blocksize
  * ![avgFPS_blocksize](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/b4747348-9417-4f6e-9e30-31a52ae0b5a3)


