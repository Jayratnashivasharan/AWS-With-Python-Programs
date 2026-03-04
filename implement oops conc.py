# write a program to implement oops concept class inheritance and polymorphism
# Base class
class Animal:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return "This animal makes a sound."

# Derived class (Inheritance)
class Dog(Animal):
    def speak(self):   # Polymorphism (method overriding)
        return f"{self.name} says: Woof!"

class Cat(Animal):
    def speak(self):   # Polymorphism (method overriding)
        return f"{self.name} says: Meow!"

class Cow(Animal):
    def speak(self):   # Polymorphism (method overriding)
        return f"{self.name} says: Moo!"

# Demonstration
animals = [Dog("Buddy"), Cat("Whiskers"), Cow("Daisy")]

for animal in animals:
    print(animal.speak())