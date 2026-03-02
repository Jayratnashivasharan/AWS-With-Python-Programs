# Write a Program to find a Mamimum and Minimum in a Tuple.
Tuple = input("Enter a Tuple of numbers separated by space: ").split()
Tuple = tuple(int(num) for num in Tuple)
Maximum = max(Tuple)
Minimum = min(Tuple)
print("The Tuple is: ", Tuple)
print("The Maximum Number in the Tuple is: ", Maximum)
print("The Minimum Number in the Tuple is: ", Minimum)