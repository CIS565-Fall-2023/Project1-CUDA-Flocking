**University of Pennsylvania, CIS 565: GPU Programming and Architecture,
Project 1 - Flocking**

* Mengxuan Huang
  * [LinkedIn](https://www.linkedin.com/in/mengxuan-huang-52881624a/)
* Tested on: Windows 11, i9-13980HX @ 2.22GHz 64.0 GB, RTX4090-Laptop 16384MB

## Outcome Summary
||boid = 5000 |boid = 100000|boid = 1000000|boid = 10000000|
|------------- |-------------|-------------|-------------|-------------|
|scene scale = 100.f|![](https://media.giphy.com/media/SUBgjPfontNnvh7cnQ/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExM3F1ZDF0ODEwMTl3c3o2OHM3aXg1c2l2bjVmNXZzMW82Y2FycWJwNyZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/5NPWXIu5iu7zIBWT9x/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExZ2d0N21jMjZjYW0wOW05dDNrNHI2MjYwZWR6ZXNrd3cwN2c2ZzB3YiZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/Fc5eFrtbwvt2F7VsVB/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExN3NrZDR3amh1bWJ4ZGY3Y3JnbXAzM21rM2N0eXV5NHh5MnZ1OXFscCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/GMCl577c5DQoZyvaPP/giphy.gif)|
|scene scale = 500.f|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExYWh5MG5mdmR5eXdwMnhuMDJzMmp6ejlkZmFweXQ1eTJyN2I2ajZ5NiZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/KkHsfVquKqJAfSAzje/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExazZxZ3I4ZGp6YjN1YXFxbDd3Z3kwYW55enQ3NXdhejZvc2lhb25sdCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/43LRlI3E7ydi5Nh4wp/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExaGNjN3R4YjR4NXNuc3lzdG1pbGlnMHBxa2tsMzJqdWJwbGZtbmR1aSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/bSW3g5dXIpdtlYRGcH/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExNXh1Mnp1ejkyanZtZGMycmNxdXRma3AycmJ6OXJidjdjNHN2b3JmOSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/zI0TgdgozKtym2oH9S/giphy.gif)|
|scene scale = 1000.f|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExbmJ1ZGZ6bndycHlwYmg1dm9kOGFuNG9ndTk4eHZuamU4d3FnaTlmeCZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/75R7lnhJ6rrTHZ7ZIH/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExYTA4cjJ2cnJ1d2d5ZDE3OXRvd3Jtb2IxZGU5eWRiZGlmc2t2NHVsZSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/8sKQXgKH2PavU2C7pJ/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExaGQ3dDFyZ2R3M3NlMXpxczhhdWJmMGZwNm8wbHJnZW91Z29pMmJ6NiZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/dISEHcsxl8j2qHkgKS/giphy.gif)|![](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExeHQ4cjZja2hnc3U1NjhqZDVlNWd4azMzaHUzcWpvdjI1OW02ZDFtOSZlcD12MV9pbnRlcm5hbF9naWZfYnlfaWQmY3Q9Zw/eFMAD5GMCSn32BdmMR/giphy.gif)|
