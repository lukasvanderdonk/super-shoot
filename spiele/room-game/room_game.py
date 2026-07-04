

import random
player_healt = 100
player_inventar = []
player_damage = 10
player_pets = []
player_damageinsgesamnt = 0
rooms = ["presentroom","fightroom","normalroom","presentroom","fightroom","presentroom","fightroom",]
monsters = ["santa Claus","Rodolph","The Grinch","The Nutcracker Prince","angry Dad"]
pesents = ["pet","parfum","whater canon"]
pets = ["dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","dog","cat","horse","parrot","mini Lukas mit riesen Ohren in Weinachts kleidung mit keksen"]
newpat = random.choice(pets)
monster_name = "santa Claus"
monster_health = 10
monster_damage = 10
kill_monster = 0



def win():
  print("win")
def attackmonster():
  global monster_name
  global monster_health
  global monster_damage
  global player_healt
  global kill_monster
  global player_damageinsgesamnt

  print(f"you fite with a {monster_name} with  {monster_health } health you health is {player_healt}")
  move = input(f"what move do you want to do? attack,give a present,run away?  ")
  if(move == "attack"):
    monster_health -= player_damage
    player_healt -= monster_damage
    player_damageinsgesamnt += player_damage
    print(f"your health is {player_healt} but the {monster_name} hase only {monster_health}")
    if(player_healt <=0):
      lose()
    elif (monster_health <= 0):
      print("you win")
      kill_monster += 1
      next = input("what do you want to do next? next room, use item   ")
      if(next == "next room"):
       next_room()
      elif(next =="use item"):
       use_item()
      else:
       print("!!!!incorrect!!!!")
    else:
       attackmonster()
  elif (move == "give a present"):
    print("give present")
  elif (move == "run away"):

    print("run")
  else:
    print("this is not a move.")
    attackmonster()



def next_room():
 global player_healt
 global next
 global monster_damage
 global monster_health
 global monster_name
 room = random.choice(rooms)
 print(f"romm : {room}")
 if(room == "fightroom"):
   monster = random.choice(monsters)
   if(monster == "santa Claus"):
     monster_name ="santa Claus"
     monster_damage =15
     monster_health =100
     attackmonster()
   elif(monster == "Rodolph"):
     monster_name ="Rodolph"
     monster_damage =5
     monster_health =50
     attackmonster()
   elif(monster == "The Grinch"):
     monster_name ="The Grinch"
     monster_damage =25
     monster_health =10

     attackmonster()
   elif(monster == "The Nutcracker Prince"):
     monster_name ="The Nutcracker Prince"
     monster_damage =5
     monster_health =30
     attackmonster()
   elif(monster == "angry Dad"):
     monster_name ="angry Dad"
     monster_damage =10
     monster_health =70.1
 elif(room == "presentroom"):
   player_inventar.append(random.choice(pesents))
   print(f"in your inventar is {player_inventar}")
   next = input("what do you want to do next? next room, use item  ")
   if(next == "next room"):
     next_room()
   elif(next =="use item"):
     use_item()
   else:
     print("!!!!incorreckt!!!!")
 elif(room == "normalroom"):
    player_healt += random.randint(5,10)
    print(f"your health is {player_healt}")
    next = input("what do you want to do next? next room, use item  ")
 if(next == "next room"):
     next_room()
 elif(next =="use item"):
   use_item()
 else:
     print("!!!!incorreckt!!!!")
def use_item():
  global player_healt
  global player_damage
  global player_inventar
  itemtouse =input(f"what item did you want to use? {player_inventar} ore no  ")
  if(itemtouse in player_inventar):
    if(itemtouse == "pet"):
      print(".")
      player_inventar.remove("pet")
      pet()
    elif(itemtouse == "parfum"):
      print(".")
      player_inventar.remove("parfum")
      player_healt += 20
      print(f"youre health is {player_healt}")
      next = input("what do you want to do next? next room, use item  ")
      if(next == "next room"):
       next_room()
      elif(next =="use item"):
       use_item()
      else:
       print("!!!!incorreckt!!!!")
    elif(itemtouse == "whater canon"):
      print(".")
      player_damage += 5
      player_inventar.remove("whater canon")
      print(f"your damage is  now {player_damage} ")
      next = input("what do you want to do next? next room, use item  ")
      if(next == "next room"):
       next_room()
      elif(next =="use item"):
       use_item()
      else:
       print("!!!!incorreckt!!!!")
  else:
    if(itemtouse== "no"):
      next = input("what do you want to do next? next room, use item  ")
      if(next == "next room"):
       next_room()
      elif(next =="use item"):
       use_item()
    else:
     print("it is not in the inventar")
     next = input("what do you want to do next? next room, use item  ")
     if(next == "next room"):
      next_room()
     elif(next =="use item"):
      use_item()
def pet():
   global player_pets
   global pets
   global newpat
   global player_healt
   global player_damage
   newpat = random.choice(pets)
   player_pets.append(newpat)
   if(newpat == "dog"):
     player_damage += 15
     player_healt += 5
     print(f"you new pat is {newpat} and so your damage is {player_damage} and your health is {player_healt}")
     print(f"your pats are {player_pets}")
   elif(newpat == "cat"):
     player_damage += 5
     player_healt += 15
     print(f"your pats are {player_pets}")
     print(f"you new pat is {newpat} and so your damage is {player_damage} and your health is {player_healt}")
   elif(newpat == "horse"):
     player_damage+= 20
     player_healt += 10
     print(f"your pats are {player_pets}")
     print(f"you new pat is {newpat} and so your damage is {player_damage} and your health is {player_healt}")
   elif(newpat == "parrot"):
     player_damage += 5
     player_healt += 55
     print(f"your pats are {player_pets}")
     print(f"you new pat is {newpat} and so your damage is {player_damage} and your health is {player_healt}")
   elif(newpat == "mini Lukas mit riesen Ohren in Weinachts kleidung mit keksen"):
     player_damage += 100000000000
     player_healt+= 10000000000000000000000
     print(f"your pats are {player_pets}")
     print(f"you new pat is the epic {newpat} and so your damage is {player_damage} and your health is {player_healt}")
def lose():
  global player_damage
  global kill_monster
  global player_pets
  print(f"you lost, you killed {kill_monster} monster! In the end, you did {player_damageinsgesamnt} damage and your pets were {player_pets}!")
  exit()
player_name = input("what is your ingame name? " )
print(f"hello "+ player_name +"")
next_room()
