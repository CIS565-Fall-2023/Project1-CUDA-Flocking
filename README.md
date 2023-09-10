**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Yian Chen
  * [LinkedIn](https://www.linkedin.com/in/yian-chen-33a31a1a8/), [personal website](https://sydianandrewchen.github.io/) etc.
* Tested on: Windows 10, AMD Ryzen 5800 HS with Radeon Graphics CPU @ 3.20GHz 16GB, NVIDIA GeForce RTX3060 Laptop 8GB


### Banner

* `N_FOR_VIS = 5,000; scene_scale=100.0f`
![](./images/banner.gif)

* `N_FOR_VIS = 500,000; scene_scale=200.0f`
![](./images/banner3.gif)

* `N_FOR_VIS = 2,000,000; scene_scale=600.0f`
![](./images/banner2.gif)


### Performance Analysis

#### Results

- Framerate change with increasing # of boids for naive, scattered uniform grid, and coherent uniform grid (with and without visualization)
![](./images/boids_no_visual.png)
![](./images/boids_with_visual.png)
- Framerate change with increasing block size
![](./images/increasing_gridSize.png)

#### Questions

* For each implementation, how does changing the number of boids affect performance? Why do you think this is?
  * For all implementation, increasing the number of boids will decrease performance. This is because the required calculations increase and the memory required also increase along with the increasing number of boids.

* For each implementation, how does changing the block count and block size affect performance? Why do you think this is?
  * As block size increases, the performance will first increase then decrease. The increasing blockSize brings higher parallelism, along with higher memory usage within each thread. As the register of each thread is limited, this will surely increase the io of local/global memory more often, thus slower the execution of each thread.

* For the coherent uniform grid: did you experience any performance improvements with the more coherent uniform grid? Was this the outcome you expected? Why or why not?
  * The performace improvements did not occur until the number of boids is increased to a certain amount. This should be the case. In a rather small amount of boids, the time saved by the coherent array is not higher than the time used to reallocate the array. 
* Did changing cell width and checking 27 vs 8 neighboring cells affect performance? Why or why not? Be careful: it is insufficient (and possibly incorrect) to say that 27-cell is slower simply because there are more cells to check!
  * Yes. According to the stats, 27 neighboring slows down performance mainly at a middle amount of boids. 27-cell is slower mainly because there are a lot of waste spent on checking irrelevant cells. There are at least 19 cells we can ensure that no adjacent boids are in.
  ![](./images/27vs8_no_visual.png)


## Part 4: Write-up

1. Take a screenshot of the boids **and** use a gif tool like [licecap](http://www.cockos.com/licecap/) to record an animations of the boids with a fixed camera. Put this at the top of your README.md. Take a look at [How to make an attractive
GitHub repo](https://github.com/pjcozzi/Articles/blob/master/CIS565/GitHubRepo/README.md).
