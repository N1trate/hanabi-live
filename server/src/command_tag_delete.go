package main

import (
	"context"
	"strconv"

	"github.com/Hanabi-Live/hanabi-live/logger"
)

// commandTagDelete is sent when a user types the "/tagdelete [tag]" command
//
// Example data:
// {
//   tableID: 123,
//   msg: 'inverted priority finesse',
// }
func commandTagDelete(ctx context.Context, s *Session, d *CommandData) {
	t, exists := getTableAndLock(ctx, s, d.TableID, !d.NoTableLock, !d.NoTablesLock)
	if !exists {
		return
	}
	if !d.NoTableLock {
		defer t.Unlock(ctx)
	}

	if !t.Running {
		s.Warning(NotStartedFail)
		return
	}

	// Sanitize, validate, and normalize the tag
	if v, err := sanitizeTag(d.Msg); err != nil {
		s.Warning(err.Error())
		return
	} else {
		d.Msg = v
	}

	tagDelete(ctx, s, d, t)
}

func tagDelete(ctx context.Context, s *Session, d *CommandData, t *Table) {
	// Local variables
	g := t.Game

	if !t.Replay {
		// See if the tag exists
		if _, ok := g.Tags[d.Msg]; ok {
			delete(g.Tags, d.Msg)

			// Send them an acknowledgement via private message to avoid spoiling information about
			// the ongoing game
			msg := "Successfully deleted the tag of \"" + d.Msg + "\"."
			chatServerSendPM(s, msg, d.Room)
		} else {
			s.Warning("The tag of \"" + d.Msg + "\" does not exist on this game yet.")
		}
		return
	}

	// Get the existing tags from the database
	var tags []string
	if v, err := models.GameTags.GetAll(t.ExtraOptions.DatabaseID); err != nil {
		logger.Error("Failed to get the tags for game ID " +
			strconv.Itoa(t.ExtraOptions.DatabaseID) + ": " + err.Error())
		s.Error(DefaultErrorMsg)
		return
	} else {
		tags = v
	}

	// Ensure that the tag exists
	if !stringInSlice(d.Msg, tags) {
		s.Warning("The tag of \"" + d.Msg + "\" does not exist on this game yet.")
		return
	}

	// Delete it from the database
	if err := models.GameTags.Delete(t.ExtraOptions.DatabaseID, d.Msg); err != nil {
		logger.Error("Failed to delete a tag for game ID " +
			strconv.Itoa(t.ExtraOptions.DatabaseID) + ": " + err.Error())
		s.Error(DefaultErrorMsg)
		return
	}

	msg := s.Username + " has deleted a game tag of \"" + d.Msg + "\"."
	chatServerSend(ctx, msg, t.GetRoomName(), d.NoTablesLock)
}
