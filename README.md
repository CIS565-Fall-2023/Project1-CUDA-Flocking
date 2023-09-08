**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Tianyi Xiao
  * [LinkedIn](https://www.linkedin.com/in/tianyi-xiao-20268524a/), [personal website](https://jackxty.github.io/), [Github](https://github.com/JackXTY).
* Tested on: Windows 11, i9-12900H @ 2.50GHz 16GB, Nvidia Geforce RTX 3070 Ti 8032MB (Personal Laptop)

### Screenshots
Below are screenshots.

With 5000 boids:
![](images/boid.gif)

With 10000 boids:
![](images/boid_10000.gif)

With 20000 boids:
![](images/boid_20000.gif)
For all tests above, other parameters are default. (block size = 128)

### Analysis

First, I made a simple analysis with fps.

| naive  | uniform | coherent |
| :----: | :----:  | :----:   |
| 800 fps | 1600 fps | 2000 fps |

Then for all analysis below, I use CUDA event to count and estimate the execution time (in million seconds) of each simulation step for all boids. The data might not be very accurate, but should be accurate enough for analysis.

What's more, all the performance test is done without visualization.

#### - How does changing the number of boids affect performance?

![](images/boid_number_graph.png)

From the graph we can see that, increasing number of boids appearently slow down the calculation of naive brute-force method, but has no appearent effect for the other two methods.

From my point of views, because in naive methods, when calculating speeds, each boid needs to traverse all boids to decide its speed. Therefore when there are more boids, each boid would spend more time on speed calculation.

For the other two methods, since we only search the cells around, so there won't be much more boids to traverse. Also, the sort would need more time with more boids, which however still won't consume too much time compared with naive method.

#### - How does changing the block count and block size affect performance?

![](images/block_size_graph.png)

Generally, we could see that, generallty the change of block size has no appearent effects for all three implementation. In this project, for my codes, the change of block size won't affect how algorithm operates, since no shared memory or other features about blocks are involved. The total threads number doesn't change as block size change, so for each streaming processor, it would handle same amount of threads.

The only exception is that, when block size is 2, the execution time for naive method has increased a lot. I think this block size is too small that, when a SM is executing a block, not every core is running a thread. So the actual number of threads executing simultaneously is smaller, which cause the GPU execute slower. And maybe since the other two methods are fast enough, the extreme small block size doesn't affect them that much.

#### - Performance improvements with the more coherent uniform grid

From the data above, appearently there is a performance improvement, which as exactly the same as I expected. After reshuffling, the global memory to access when computing the velocity is reduced, and accessing global memory is time consuming.

#### - Did changing cell width and checking 27 vs 8 neighboring cells affect performance?

From my test, I found that there is no significant difference between 8 or 27 neighboring cells, until I increase the boid number to 100000. These tests are down in coherent mode with 128 block size.

|     | 5000  | 10000 | 50000 | 100000 |
| :----: | :----: | :----:  | :----:   |:----:   |
| 8:  | 0.20 | 0.20 | 0.23 | 0.35 |
| 27:  | 0.20 | 0.20 | 0.22 | 0.29 |

I think, when there are not many boids, the actual number of boids in neighbor cells doesn't differ much. However, when there are 100000 boids, boids are divided quite averagely in space. Since the cell size if 1/2 in 27 neighbor cell, the total neighbor cell space size ratio of 27 and 8 cells is 27 * (1/2) * (1/2) / 8 = 27/32. So there are less boids to travserse in 27 neighbor modes, and thus it's faster.

#### - Grid-Looping Optimization
After I implemented the grid-looping optimization and set cell width as max_Distance, the average time is about 0.27 for 100000 boids, which has some improvement from 27 neighbor mode. I think some cells among the 27 cells are further removed, and when calculating the cell boundary, there are fewer computation.