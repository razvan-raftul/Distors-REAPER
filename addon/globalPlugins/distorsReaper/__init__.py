# Distors REAPER – addon NVDA
# Citește mesajele scrise de scriptul „Distors REAPER.lua” din REAPER.
# La distors: un bip scurt, apoi NVDA spune pe ce pistă și cu câți dB să scazi volumul.

import os
import re
import threading

import globalPluginHandler
import queueHandler
import tones
import ui
from logHandler import log

from . import actualizare

SCRIPT_LUA = os.path.join(os.path.dirname(__file__), "Distors REAPER.lua")
FISIER = os.path.join(os.environ.get("TEMP", ""), "reaper_distors.txt")


def citeste():
	try:
		with open(FISIER, encoding="utf-8", errors="replace") as f:
			date = f.read()
	except OSError:
		return None, None
	ident, _, mesaj = date.partition("\n")
	return ident.strip(), mesaj.strip()


def pune_scriptul_in_reaper():
	"""Pune scriptul din addon peste cel folosit de REAPER, ca după o actualizare REAPER să aibă varianta nouă.
	Caută în __startup.lua de unde pornește REAPER scriptul; dacă nu-l găsește, îl pune în Scripts și îl adaugă la pornire."""
	try:
		with open(SCRIPT_LUA, "rb") as f:
			nou = f.read()
	except OSError:
		return
	resurse = os.path.join(os.environ.get("APPDATA", ""), "REAPER")
	if not os.path.isdir(resurse):
		return                                     # REAPER nu e instalat (sau e portabil)
	startup = os.path.join(resurse, "Scripts", "__startup.lua")
	try:
		with open(startup, encoding="utf-8", errors="replace") as f:
			continut = f.read()
	except OSError:
		continut = ""
	cai = [c for c in re.findall(r"\[\[([^\]]*Distors REAPER[^\]]*\.lua)\]\]", continut) if c]
	if not cai:
		cale = os.path.join(resurse, "Scripts", "Distors REAPER.lua")
		cai = [cale]
		try:
			os.makedirs(os.path.dirname(startup), exist_ok=True)
			with open(startup, "a", encoding="utf-8") as f:
				f.write("\n-- Distors REAPER: pornește detectorul de distors\n"
					"do local id = reaper.AddRemoveReaScript(true, 0, [[" + cale + "]], true)\n"
					"if id and id ~= 0 then reaper.Main_OnCommand(id, 0) end end\n")
		except OSError as e:
			log.error("Distors REAPER: __startup.lua: %s" % e)
	for cale in cai:
		try:
			with open(cale, "rb") as f:
				if f.read() == nou:
					continue
		except OSError:
			pass
		try:
			with open(cale, "wb") as f:
				f.write(nou)
		except OSError as e:
			log.error("Distors REAPER: nu am putut scrie %s: %s" % (cale, e))


class GlobalPlugin(globalPluginHandler.GlobalPlugin):

	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)
		self._opreste = threading.Event()
		self._ultimul = citeste()[0]   # nu anunțăm ce era deja în fișier la pornirea NVDA
		self._fir = threading.Thread(target=self._bucla, daemon=True)
		self._fir.start()
		threading.Thread(target=pune_scriptul_in_reaper, daemon=True).start()
		actualizare.verifica_mai_tarziu()

	def _bucla(self):
		while not self._opreste.wait(0.1):
			ident, mesaj = citeste()
			if ident and ident != self._ultimul:
				self._ultimul = ident
				if mesaj:
					queueHandler.queueFunction(queueHandler.eventQueue, self._anunta, mesaj)

	def _anunta(self, mesaj):
		if mesaj.startswith("Distors"):
			tones.beep(1200, 80)
		ui.message(mesaj)

	def terminate(self):
		self._opreste.set()
		super().terminate()
