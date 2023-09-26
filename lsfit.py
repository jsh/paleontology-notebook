#!/usr/bin/env python3

import numpy as np

# Load data from a file with two columns (x and y)
def load_data(filename):
    data = np.loadtxt(filename)
    x = data[:, 0]
    y = data[:, 1]
    return x, y

# Perform the least-squares fit for a linear equation y = mx + b
def linear_regression(x, y):
    n = len(x)
    sum_x = np.sum(x)
    sum_y = np.sum(y)
    sum_xy = np.sum(x * y)
    sum_x_squared = np.sum(x**2)

    m = (n * sum_xy - sum_x * sum_y) / (n * sum_x_squared - sum_x**2)
    b = (sum_y - m * sum_x) / n

    # Calculate R^2
    y_pred = m * x + b
    ssr = np.sum((y_pred - y)**2)
    sst = np.sum((y - np.mean(y))**2)
    r_squared = 1 - (ssr / sst)

    return m, b, r_squared

if __name__ == "__main__":
    data_file = "/dev/stdin"  # Replace with your data file
    x, y = load_data(data_file)
    m, b, r_squared = linear_regression(x, y)
    print(f"Linear Equation: y = {m:.4f}x + {b:.4f}")
    print(f"R^2 (Coefficient of Determination): {r_squared:.4f}")

