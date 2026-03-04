# write program to find common element in two list
# Program to find common elements in two lists

# Input lists
list1 = [1, 2, 3, 4, 5]
list2 = [4, 5, 6, 7, 8]

# Find common elements using set intersection
common_elements = list(set(list1) & set(list2))

print("Common elements:", common_elements)