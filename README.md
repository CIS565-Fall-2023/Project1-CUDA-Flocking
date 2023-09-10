**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Han Wang

* Tested on: Windows 11, 11th Gen Intel(R) Core(TM) i9-11900H @ 2.50GHz  22GB, GTX 3070 Laptop GPU

### Output display
The following parts are required GIF :

## NaiveGrid
![Unlock FPS](images/hw2.gif)

## CoherentGrid
![Unlock FPS](images/hw.gif)

Include screenshots, analysis, etc. (Remember, this is public, so don't put
anything here that you don't want to share with the world.)

### Part3 analysis

For each implementation, how does changing the number of boids affect performance? Why do you think this is?
here are the diagram for the number of bids that affect the performance:









For each implementation, how does changing the block count and block size affect performance? Why do you think this is?







For the coherent uniform grid: did you experience any performance improvements with the more coherent uniform grid? Was this the outcome you expected? Why or why not?






Did changing cell width and checking 27 vs 8 neighboring cells affect performance? Why or why not? Be careful: it is insufficient (and possibly incorrect) to say that 27-cell is slower simply because there are more cells to check!
