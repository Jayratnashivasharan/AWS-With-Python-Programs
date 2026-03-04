# write program to find frequency of each charachter
# Program to find frequency of each character

# Input string
text = input("Enter a string: ")

# Create a dictionary to store frequencies
frequency = {}

for char in text:
    if char in frequency:
        frequency[char] += 1
    else:
        frequency[char] = 1

# Display the frequency of each character
print("Character frequencies:")
for char, freq in frequency.items():
    print(f"'{char}': {freq}")