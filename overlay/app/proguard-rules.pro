# R8 keep rules for :app. Hilt and kotlinx-serialization ship consumer rules; Navigation 3 (1.2.0) ships
# none, and needs none: back-stack saving looks up each @Serializable key's serializer by reflection
# (INSTANCE / Companion + serializer()), which kotlinx-serialization's rules keep. Add rules here only for
# reflection the app itself does. Audit with the r8-analyzer skill.
