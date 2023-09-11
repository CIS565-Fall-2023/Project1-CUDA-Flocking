# CIS 565: GPU Programming and Architecture

## Project 1 - Flocking

![Boids 1.3](images/boids13.gif)

**Jason Xie**

[🤓 LinkedIn](https://linkedin.com/in/jia-chun-xie)

[😇 my website](https://jchunx.dev)

[🥵 X (formerly 🐦)](https://x.com/codemonke_)

Tested on: Ubuntu 22.04, i5-8400, RTX 3060Ti, personal machine

## Results

## Performance Analysis

### FPS vs. Number of Boids

![FPS vs. Number of Boids](images/boids-perf.png)

#### Naive

|# Boids| FPS    |
|-------|--------|
| 1000  | 1900 |
| 10000 |  215   |
| 100000|  6   |

#### Scattered Uniform

|# Boids| FPS    |
|-------|--------|
| 1000  |  4000  |
| 10000 |  2100  |
| 100000|  270   |
| 1000000|  6   |

#### Coherent Uniform

|# Boids| FPS    |
|-------|--------|
| 1000  |  3800  |
| 10000 |  2800  |
| 100000|  280   |
| 1000000|  1    |

### FPS vs. Block Size



