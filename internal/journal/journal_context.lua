--@ module = true

local widgets = require 'gui.widgets'
local utils = require('utils')
local DummyJournalContext = reqscript('internal/journal/contexts/dummy').DummyJournalContext
local FortressJournalContext = reqscript('internal/journal/contexts/fortress').FortressJournalContext
local AdventurerJournalContext = reqscript('internal/journal/contexts/adventure').AdventurerJournalContext

JOURNAL_CONTEXT_MODE = {
  FORTRESS='fortress',
  ADVENTURE='adventure',
  DUMMY='dummy'
}

function detect_journal_context_mode()
  if dfhack.world.isFortressMode() then
    return JOURNAL_CONTEXT_MODE.FORTRESS
  elseif dfhack.world.isAdventureMode() then
    return JOURNAL_CONTEXT_MODE.ADVENTURE
  else
    qerror('unsupported game mode')
  end
end

function journal_context_factory(journal_context_mode, save_prefix)
  if journal_context_mode == JOURNAL_CONTEXT_MODE.FORTRESS then
    return FortressJournalContext{save_prefix}
  elseif journal_context_mode == JOURNAL_CONTEXT_MODE.ADVENTURE then
    local interactions = df.global.adventure.interactions
    if #interactions.party_core_members == 0 or interactions.party_core_members[0] == nil then
      qerror('Can not identify party core member')
    end

    local adventurer_id = interactions.party_core_members[0]

    return AdventurerJournalContext{
      save_prefix,
      adventurer_id=adventurer_id
    }
  elseif journal_context_mode == JOURNAL_CONTEXT_MODE.DUMMY then
    return DummyJournalContext{}
  else
    qerror('unsupported game mode')
  end
end
