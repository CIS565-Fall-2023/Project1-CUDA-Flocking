**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Licheng CAO
  * [LinkedIn](https://www.linkedin.com/in/licheng-cao-6a523524b/)
* Tested on: Windows 10, i7-10870H @ 2.20GHz 32GB, GTX 3060 6009MB

### Result (65536 Boids)
![boid](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/1cb4f564-45ab-450e-b207-078f50b25ec1)
### Analysis
* the number of boids
  * As shown in Figure1, the FPS decreases as the number of boids increases. The reason for this is that the number of boids that need to be processed in each thread increases. Among all step methods, the naive method is effected by the number of boids the most, because it considers all boids in each thread. The scattered method largely improves the performance, it only considers boids in the nearby grid, so the number of boids each thread needs to consider is largely reduced. In this method, I also search the nearby grid in a specific order that the grid will be accessed contiguously. The coherent method gets slight performance improvement over the scattered method, it rearranges the position and velocity array of boids to make the inforamtion of the boids that stay in the same grid is contiguous in memory. So when the program wants to iterate over all the boids in the same grid, it can get the information with lesser time.
  * Figure1
![avgFPS_numboids](https://github.com/LichengCAO/Project1-CUDA-Flocking/assets/81556019/5f1a855f-b75f-411d-97f1-535e59112a31)
* the blocksize
  * Table1
  * | blocksize | 32    | 64    | 96    | 128   | 160   |  192  |  224  |
    | :---:     | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
    | naiveFPS  | 0.323 | 0.454 | 0.452 | 0.458 | 0.449 | 0.455 | 0.457 |
    | ScatteredFPS|129.62|174.728 | 181.97 | 181.566 | 179.985 | 181.666| 177.534 |
    |CoherentFPS|231.937|	270.333|	273.499|	270.334|	269.264	|269.608|	267.44|

