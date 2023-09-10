import matplotlib.pyplot as plt

N = [r"$5x10^{}$".format(i) for i in range(2, 7)]

# Drawing increasing boids, with visuals
fps_brutalForce = [4802.94, 707.513, 42.102, 0.457157, 0.0]
fps_scatteredGrid = [4104.64, 3761.42, 1748.94, 416.962, 18.5537]
fps_coherentGrid = [3738.6, 3349.59, 1713.82, 761.368, 57.0016]

plt.xlabel("N count")
plt.ylabel("FPS")
plt.plot(N, fps_brutalForce, label="brutalForce", color="r", marker="o")
plt.plot(N, fps_scatteredGrid, label="scatteredGrid", color="g", marker="o")
plt.plot(N, fps_coherentGrid, label="coherentGrid", color="b", marker="o")
plt.legend(labels=["brutalForce", "scatteredGrid", "coherentGrid"])
plt.title("FPS of kernel under different method (With visulization)")
# plt.show()
plt.savefig("../images/boids_with_visual.png")

plt.clf()

# Drawing increasing boids, no visuals
fps_brutalForce = [8297.48, 1227.13, 42.882, 0.46393, 0.0]
fps_scatteredGrid = [7666.14, 7279.71, 4348.93, 380.379, 18.6696]
fps_coherentGrid = [7383.36, 7034.57, 4743.67, 683.372, 57.848]

plt.xlabel("N count")
plt.ylabel("FPS")
plt.plot(N, fps_brutalForce, label="brutalForce", color="r", marker="o")
plt.plot(N, fps_scatteredGrid, label="scatteredGrid", color="g", marker="o")
plt.plot(N, fps_coherentGrid, label="coherentGrid", color="b", marker="o")
plt.legend(labels=["brutalForce", "scatteredGrid", "coherentGrid"])
plt.title("FPS of kernel under different method (No visulization)")
# plt.show()
plt.savefig("../images/boids_no_visual.png")

plt.clf()

# Drawing 27-cell vs 8-cell
plt.xlabel("N count")
plt.ylabel("FPS")
fps_scatteredGrid27Neighbors = [7285.03, 6472.57, 3955.12, 353.385, 18.667]
fps_scatteredGrid8Neighbors = [7666.14, 7279.71, 4348.93, 380.379, 18.6696]
plt.plot(N, fps_scatteredGrid27Neighbors, label="27-cell", marker="o")
plt.plot(N, fps_scatteredGrid8Neighbors, label="8-cell", marker="o")
plt.legend(labels=["27-cell", "8-cell"])
plt.title("FPS of 27-cell vs 8-cell (No visualization)")
# plt.show()
plt.savefig("../images/27vs8_no_visual.png")

plt.clf()


# Drawing increasing blockSize

blockSize = [r"$2^{}$".format(i) for i in range(2, 11)]
fps_coherentGridBlockSizeChanged = [ 11.7512, 18.7417,28.524,41.9919, 57.0016, 62.4268, 64.3508, 61.0085, 59.5032]
plt.xlabel("Block size")
plt.ylabel("FPS")
plt.plot(blockSize, fps_coherentGridBlockSizeChanged, marker="o")
plt.title("FPS of coherent grid over increasing grid size (With visualization)")
# plt.show()
plt.savefig("../images/increasing_gridSize.png")

if __name__ == "__main__":
    pass