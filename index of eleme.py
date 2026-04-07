# write a progarm to find index of element in a tuple
# Program to find the index of an element in a tuple

# Define a tuple
my_tuple = (10, 20, 30, 40, 50)

element = int(input("Enter the element to find: "))

# Check if element exists in tuple
if element in my_tuple:
    index = my_tuple.index(element)
    print(f"The index of {element} is: {index}")
else:
    print(f"{element} is not present in the tuple.")