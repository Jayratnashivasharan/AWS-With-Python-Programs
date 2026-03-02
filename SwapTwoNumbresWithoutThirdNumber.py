# Write a program to Swap two numbers without using a third variable.
a = int(input("Enter First Number: "))
b = int(input("Enter Second Number: "))
print("Before Swapping: a =", a, "b =", b)
a = a + b
b = a - b
a = a - b
print("After Swapping: a =", a, "b =", b)