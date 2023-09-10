**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Xiaoxiao Zou
  * [LinkedIn](https://www.linkedin.com/in/xiaoxiao-zou-23482a1b9/)
* Tested on: Windows 11, AMD Ryzen 9 7940HS @ 4.00 GHz, RTX 4060 Laptop 

Include screenshots, analysis, etc. (Remember, this is public, so don't put
anything here that you don't want to share with the world.)

## Output
![](images/result.gif)

## Performance Analysis

Note: Since I use the title bar to observe the FPS, I am not able to get the accurate data for visualized ones (FPS is fixed there).

Q: For each implementation, how does changing the number of boids affect performance? Why do you think this is?

Changing number of boids significantly impact the performance. As the number of boid increase, the FPS decreases significantly. Since number of boids count will affect number of neighbors each boid need to search around it, the time cost for each neighboring search will increase. 

Q: For each implementation, how does changing the block count and block size affect performance? Why do you think this is?

The change of block size almost not influence the performance with boids count 20000 when the block size is larger than 64. When block size is small, the increase of blocks size will improve the performance. Since the block size will change the number of block, when block size is really small, the block counts will become larger. Then, if GPU does not have enough blocks for computing, the performance will get lower.

Q: For the coherent uniform grid: did you experience any performance improvements with the more coherent uniform grid? Was this the outcome you expected? Why or why not?

A: Coherent grid gives slightly better performance compared to scattered grid. Since for scattered grid, it takes a long time to sort the boid every frame, if we also sort the position array, the next round, when we label the boid, it will almost in right order in terms of grid since boid will not travel too far. Then, it takes less time averagely for sorting and accessing the elements on array indices, but longer time to reshuffle two arrays. 

Q: Did changing cell width and checking 27 vs 8 neighboring cells affect performance? Why or why not? Be careful: it is insufficient (and possibly incorrect) to say that 27-cell is slower simply because there are more cells to check!

A: 27 cells will not always hurt performance since the overall volume is smaller than 8 cells, when the density went high, the number of neighbors need to be checked for 27 cells is smaller than number of neighbors need to be checked for 8 cells.