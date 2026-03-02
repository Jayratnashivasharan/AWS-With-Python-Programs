# Write a program Find the largest and smallest number in a list of numbers.
Numbers = input("Enter a list of numbers separated by space: ").split()
Numbers = [int(num) for num in Numbers]
Largest = max(Numbers)
Smallest = min(Numbers)
print("The Largest Number is: ", Largest)
print("The Smallest Number is: ", Smallest)
