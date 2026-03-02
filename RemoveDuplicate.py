# Write a program Remove duplicate characters from a given string.
String = input("Enter a String:")
UniqueString = ""
for char in String:
    if char not in UniqueString:
        UniqueString += char
print("String after removing duplicates: ", UniqueString)