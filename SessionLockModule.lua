-- SessionLock.lua as child of DataStoreModule
local DS = game:GetService("DataStoreService")
local LOCK_STORE_NAME = "SessionLocks_v1" -- name used for lock datastore
local LOCK_TIMEOUT = 60                   -- seconds lock is valid (tweak)
local LOCK_MODE = "soft"                  -- "soft" or "strict"
-- soft = allow join but set a flag/notify. strict = kick if lock can't be acquired.

local lockStore = DS:GetDataStore(LOCK_STORE_NAME)

local SessionLock = {}

-- Try to acquire lock for a userId. Returns true if we own the lock (or best-effort on DS error).
function SessionLock.TryAcquire(userId)
	local key = "lock_" .. tostring(userId)
	local ok, newVal = pcall(function()
		return lockStore:UpdateAsync(key, function(old)
			local now = os.time()
			-- If there is a valid lock by another job, keep it
			if old and type(old) == "table" and old.expire and old.expire > now and old.ownerJob and old.ownerJob ~= game.JobId then
				return old
			end
			-- Otherwise set/refresh lock for this job
			return { ownerJob = game.JobId, expire = now + LOCK_TIMEOUT }
		end)
	end)

	if not ok then
		-- DataStore error: be permissive so players aren't unnecessarily kicked; log warning
		warn("[SessionLock] DataStore UpdateAsync failed for user", userId, "- allowing join (DS error).")
		return true
	end

	-- If the returned lock belongs to this job, we have it
	if newVal and newVal.ownerJob == game.JobId then
		return true
	end
	-- otherwise someone else holds it
	return false
end

-- Release lock (best-effort). Use RemoveAsync if available.
function SessionLock.Release(userId)
	local key = "lock_" .. tostring(userId)
	pcall(function()
		if lockStore.RemoveAsync then
			lockStore:RemoveAsync(key)
		else
			-- fallback: expire immediately by UpdateAsync
			lockStore:UpdateAsync(key, function(_) return {ownerJob = nil, expire = os.time() - 1} end)
		end
	end)
end

-- Expose mode so caller can decide what to do when TryAcquire fails
function SessionLock.Mode()
	return LOCK_MODE
end

-- Expose constants for easy tuning
SessionLock.LOCK_TIMEOUT = LOCK_TIMEOUT

return SessionLock
